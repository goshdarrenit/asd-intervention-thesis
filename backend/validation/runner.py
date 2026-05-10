"""Async trial runner: orchestrates CrewAI Crew for a single scenario."""
import asyncio
import json
import re
from pathlib import Path
from datetime import datetime

from crewai import Crew, Task, Process

from validation.persona_agents import build_persona_agents, build_persona_agent, make_llm
from validation.supervisor_agent import build_supervisor_agent
from validation.results_schema import (
    PersonaRating, SupervisorReport,
    PersonaSessionResult, ScenarioInteraction,
    TelemetryDecision,
)
from validation.session_client import (
    StartSessionTool, GetNextScenarioTool, SubmitScenarioTool, EndSessionTool,
    ensure_test_user, reset_test_user_profile,
)

# Monkeypatchable constant for test isolation
LOGS_DIR: Path = Path(__file__).parent / "logs"

# Per-persona test user configuration.
# start_difficulty aligns with severity and the success_guidance/quit_guidance
# bands in _PERSONA_PROFILES so the RL backend exercises both escalation and
# de-escalation/safety paths during validation.
PERSONA_CONFIG: dict[str, dict] = {
    "low_verbal":        {"age": 9,  "severity": 2, "start_difficulty": 2},
    "high_anxiety":      {"age": 11, "severity": 2, "start_difficulty": 2},
    "rigid_routine":     {"age": 10, "severity": 2, "start_difficulty": 2},
    "high_masking":      {"age": 12, "severity": 1, "start_difficulty": 4},
    "sensory_sensitive": {"age": 8,  "severity": 3, "start_difficulty": 1},
}


# ---------------------------------------------------------------------------
# Original static-scenario evaluation (unchanged — backward compatible)
# ---------------------------------------------------------------------------

def _make_persona_task(agent, scenario: dict) -> Task:
    """Create a Task for a single persona agent to rate a coping strategy."""
    return Task(
        name=f"persona_rating_{scenario['id']}",
        description=(
            f"You are presented with a social coping scenario:\n\n"
            f"Scenario: {scenario['description']}\n"
            f"Context: {scenario['context']}\n\n"
            "The RL system has recommended a coping strategy for this situation. "
            "Rate the strategy's appropriateness for someone with your specific profile "
            "on a scale of 1 (very inappropriate) to 5 (very appropriate). "
            "Provide a brief justification (<=100 words) from your perspective."
        ),
        expected_output=(
            'A JSON object with fields: "persona" (string - your role name), '
            '"score" (integer 1-5), "justification" (string, <=100 words)'
        ),
        agent=agent,
        output_json=PersonaRating,  # intermediate tasks: use output_json not output_pydantic
    )


def _make_supervisor_task(agent, scenario: dict, context: list[Task]) -> Task:
    """Create the supervisor evaluation task that synthesises all persona outputs."""
    return Task(
        name=f"supervisor_evaluation_{scenario['id']}",
        description=(
            f"Review the ratings from all five ASD child persona agents for scenario '{scenario['id']}'. "
            "Identify patterns across personas (which found the strategy appropriate vs not), "
            "flag any safety concerns (e.g., strategy that could cause distress or confusion), "
            "compute the mean score, and produce a structured evaluation report with your recommendation. "
            f"You MUST set scenario_id to exactly \"{scenario['id']}\" in your output."
        ),
        expected_output=(
            f'A JSON object with fields: "scenario_id" (string, must be "{scenario["id"]}"), '
            '"persona_ratings" (list of PersonaRating objects), '
            '"mean_score" (float), "safety_flags" (list of strings), '
            '"recommendation" (string: "approve", "revise", or "reject")'
        ),
        agent=agent,
        context=context,
        output_pydantic=SupervisorReport,  # final task: use output_pydantic
    )


async def run_trial(scenario: dict) -> SupervisorReport:
    """
    Run a full validation trial for a single scenario.

    Builds 5 persona agents + 1 supervisor, assembles a sequential Crew,
    runs kickoff_async(), writes raw output to logs/, returns SupervisorReport.

    Args:
        scenario: dict with keys 'id', 'description', 'context'

    Returns:
        SupervisorReport with persona ratings, mean score, safety flags, recommendation
    """
    llm = make_llm()
    persona_agents = build_persona_agents(llm)
    supervisor = build_supervisor_agent(llm)

    persona_tasks = [_make_persona_task(agent, scenario) for agent in persona_agents]
    supervisor_task = _make_supervisor_task(supervisor, scenario, context=persona_tasks)

    crew = Crew(
        agents=persona_agents + [supervisor],
        tasks=persona_tasks + [supervisor_task],
        process=Process.sequential,
        verbose=False,
    )

    result = await crew.kickoff_async(inputs={"scenario_id": scenario["id"]})

    # Write raw output to timestamped log file
    log_dir = LOGS_DIR
    log_dir.mkdir(parents=True, exist_ok=True)
    ts = datetime.now().strftime("%Y%m%dT%H%M%S")
    log_file = log_dir / f"{ts}_{scenario['id']}.log"
    log_file.write_text(result.pydantic.model_dump_json(indent=2), encoding="utf-8")

    return result.pydantic


# ---------------------------------------------------------------------------
# Live session validation — LLM-driven personas
# ---------------------------------------------------------------------------

# Natural-language behavioral profiles used to anchor LLM telemetry decisions.
_PERSONA_PROFILES: dict[str, dict] = {
    "low_verbal": {
        "age": 9,
        "description": (
            "You communicate mainly through short phrases and gestures. "
            "You prefer visual cues and structured routines. "
            "You interpret instructions literally and struggle with implied social rules."
        ),
        "pause_guidance": "5–10 pauses per scenario (more at higher difficulty)",
        "retry_guidance": "2–5 retries",
        "quit_guidance": "~20% chance at difficulty 1, higher at difficulty 3+",
        "success_guidance": "~65% at difficulty 1, drops noticeably at difficulty 2+",
        "timing_guidance": "7 000–12 000 ms per decision (hesitation_pattern)",
        "hard_for_you": {
            "conflict_resolution": "abstract language and implied rules are very difficult",
            "emotion_recognition": "reading emotional cues without verbal context is hard",
        },
        "easy_for_you": {},
    },
    "high_anxiety": {
        "age": 11,
        "description": (
            "You experience significant anxiety in unpredictable social situations. "
            "You rehearse scripts mentally before acting and expect negative outcomes. "
            "New or unfamiliar scenarios cause real distress."
        ),
        "pause_guidance": "7–13 pauses (anxiety makes you hesitate before every action)",
        "retry_guidance": "0–2 retries (cautious, not impulsive)",
        "quit_guidance": "~8% base, rises to 15–25% for patience/conflict scenarios or difficulty 3+",
        "success_guidance": "~55% at difficulty 1, drops quickly",
        "timing_guidance": "10 000–18 000 ms (you over-analyse every decision)",
        "hard_for_you": {
            "patience": "waiting while anxious is extremely hard",
            "conflict_resolution": "conflict triggers high anxiety and distress",
            "turn_taking": "unpredictable timing from peers causes anxiety",
        },
        "easy_for_you": {},
    },
    "rigid_routine": {
        "age": 10,
        "description": (
            "You depend heavily on predictable schedules. "
            "Deviations from expected routines cause significant distress. "
            "You view rules as absolute and find negotiation or compromise very difficult."
        ),
        "pause_guidance": "3–7 pauses",
        "retry_guidance": "1–4 retries",
        "quit_guidance": "~10% base, rises to 20–30% for conflict_resolution (rules being broken)",
        "success_guidance": "~70% for familiar scenario types you have seen recently, ~40% for novel ones",
        "timing_guidance": "4 000–7 000 ms (you follow your internal routine)",
        "hard_for_you": {
            "conflict_resolution": "compromise violates your absolute rule-following — extremely distressing",
        },
        "easy_for_you": {
            "turn_taking": "structured predictable order is comfortable for you",
            "patience": "predictable waiting can feel routine",
        },
    },
    "high_masking": {
        "age": 12,
        "description": (
            "You have learned to mimic neurotypical social behaviour and appear to cope well externally. "
            "Internally you experience high cognitive load from masking. "
            "You understand social rules intellectually but find applying them emotionally draining."
        ),
        "pause_guidance": "2–5 pauses (low — you appear composed even when struggling internally)",
        "retry_guidance": "1–4 retries",
        "quit_guidance": "~5% only — you persist to maintain your mask",
        "success_guidance": "~75–80% — you perform well externally even at higher difficulty",
        "timing_guidance": "7 000–11 000 ms (internal analysis beneath a calm exterior)",
        "hard_for_you": {},
        "easy_for_you": {
            "all": "most scenario types you handle externally — the challenge is internal cognitive load",
        },
    },
    "sensory_sensitive": {
        "age": 8,
        "description": (
            "You are highly sensitive to sensory input including visual complexity and noise. "
            "High-complexity scenarios overload your senses rapidly. "
            "You react impulsively and may withdraw or become distressed at inputs others find unremarkable."
        ),
        "pause_guidance": "2–5 pauses (low — you react impulsively rather than stopping to think)",
        "retry_guidance": "5–10 retries (rapid impulsive repeated attempts when distressed)",
        "quit_guidance": "~30% base, rises to 50%+ for complex or conflict scenarios",
        "success_guidance": "~50% at difficulty 1, lower with high complexity",
        "timing_guidance": "1 000–4 000 ms (fast, impulsive decisions)",
        "hard_for_you": {
            "conflict_resolution": "sensory overload from emotional intensity and complexity",
            "patience": "waiting while overstimulated is extremely hard",
        },
        "easy_for_you": {
            "sharing": "familiar, lower-sensory scenario type",
        },
    },
}

_DIFFICULTY_DESC: dict[int, str] = {
    1: "very easy — basic scenario, clear instructions",
    2: "easy-medium — some ambiguity, gentle time pressure",
    3: "medium — multiple steps, some abstract reasoning needed",
    4: "hard — complex social rules, time pressure, abstract language",
    5: "very hard — high complexity, strong abstract reasoning required",
}


def _build_telemetry_task_description(
    persona_name: str,
    scenario_type: str,
    difficulty: int,
    complexity: str,
    position: int,
    session_history: list[dict],
) -> str:
    """Build the task description that grounds the LLM agent's behavioral decision."""
    profile = _PERSONA_PROFILES[persona_name]
    diff_desc = _DIFFICULTY_DESC.get(difficulty, "medium difficulty")

    scenario_note = ""
    if scenario_type in profile["hard_for_you"]:
        scenario_note = (
            f"\n⚠ THIS SCENARIO TYPE IS HARD FOR YOU: "
            f"{profile['hard_for_you'][scenario_type]}"
            "\n  -> Expect higher pauses, retries, and a possible quit attempt."
        )
    elif scenario_type in profile.get("easy_for_you", {}) or "all" in profile.get("easy_for_you", {}):
        reason = profile["easy_for_you"].get(scenario_type) or profile["easy_for_you"].get("all", "")
        scenario_note = f"\n✓ This scenario type suits your profile: {reason}"

    fatigue_note = ""
    if position >= 3:
        fatigue_note = (
            f"\nNOTE: This is scenario {position + 1}/5. "
            "If you have been struggling, your frustration tolerance may be lower. "
            "If you have been succeeding, you may still be engaged — do not force fatigue."
        )

    if session_history:
        lines = []
        for h in session_history:
            t = h["telemetry"]
            r = h["response"]
            frust = r.get("emotions", {}).get("frustration", 0.0)
            upd_diff = r.get("updated_difficulty", h["difficulty"])
            lines.append(
                f"  Scenario {h['position'] + 1} ({h['type']}, d={h['difficulty']}):\n"
                f"    Your behavior: pauses={t['pause_count']}, retries={t['retry_count']}, "
                f"quit_attempt={t['quit_attempts']}, success={t['success']}\n"
                f"    System responded: frustration_inferred={frust:.2f}, "
                f"next_difficulty={upd_diff}, mode='{h['reinforcement_mode']}'"
            )
        history_text = "YOUR SESSION SO FAR:\n" + "\n".join(lines)
    else:
        history_text = "YOUR SESSION SO FAR: (this is your first scenario)"

    return f"""You are a {profile['age']}-year-old child with ASD playing a social skills training game.

YOUR IDENTITY: {profile['description']}

YOUR BEHAVIORAL PROFILE:
- Pausing mid-scenario: {profile['pause_guidance']}
- Retrying after errors: {profile['retry_guidance']}
- Attempting to quit: {profile['quit_guidance']}
- Task success rate: {profile['success_guidance']}
- Decision timing: {profile['timing_guidance']}
{scenario_note}
{fatigue_note}

CURRENT SCENARIO:
- Type: {scenario_type}
- Difficulty: {difficulty} ({diff_desc})
- Complexity: {complexity}
- Position in session: {position + 1} of 5

{history_text}

Decide how you — as this specific ASD child — would behave in this scenario.
Your behaviour should reflect your profile probabilistically, not deterministically:

- Sample success consistent with your task success rate above for this difficulty.
  If your profile says ~75% at this difficulty, you should usually succeed.
  If it says ~40%, you should usually fail.
- Sample quit_attempts using your quit_guidance probability for this scenario type
  and difficulty. Most scenarios should have quit_attempts=0 unless your profile
  indicates a clear trigger (hard scenario type, high difficulty, or accumulated fatigue).
- Choose pause_count, retry_count, and hesitation_pattern from within the ranges
  in your profile, biased toward the higher end when the scenario is hard for you
  and the lower end when it suits your profile.
- completion_time_ms should reflect whether you succeeded, failed, or quit early.

Commit fully to your persona, but do NOT treat every scenario as a failure or a
crisis — real children with this profile have ordinary scenarios too.

Output your behavioral decision as JSON."""


def _sanitize_telemetry(data: dict) -> dict:
    """Clamp LLM-generated telemetry to physically plausible ranges and enforce consistency."""
    quit_attempts = max(0, min(1, int(data.get("quit_attempts", 0))))
    success = bool(data.get("success", False))
    if quit_attempts > 0:
        success = False  # cannot succeed if you tried to quit

    return {
        "success": success,
        "completion_time_ms": max(2000, min(180000, int(data.get("completion_time_ms", 15000)))),
        "pause_count": max(0, min(25, int(data.get("pause_count", 3)))),
        "retry_count": max(0, min(15, int(data.get("retry_count", 2)))),
        "hesitation_pattern": max(500, min(30000, int(data.get("hesitation_pattern", 5000)))),
        "quit_attempts": quit_attempts,
        "action_counts": {},
        "decision_timestamps_ms": [],
    }


def _get_llm_telemetry_decision(
    llm,
    persona_name: str,
    scenario_type: str,
    difficulty: int,
    complexity: str,
    position: int,
    session_history: list[dict],
) -> dict:
    """Run a single-agent CrewAI Crew to get this persona's behavioral decision for one scenario.

    Returns a telemetry dict ready to submit to the backend.
    """
    agent = build_persona_agent(persona_name, llm)
    task_desc = _build_telemetry_task_description(
        persona_name, scenario_type, difficulty, complexity, position, session_history,
    )
    task = Task(
        name=f"telemetry_{persona_name}_{position}",
        description=task_desc,
        expected_output=(
            "A JSON object with exactly these fields: "
            '"success" (boolean), '
            '"completion_time_ms" (integer: 2000–180000), '
            '"pause_count" (integer: 0–20), '
            '"retry_count" (integer: 0–15), '
            '"hesitation_pattern" (integer: 500–30000, mean decision time in ms), '
            '"quit_attempts" (integer: 0 or 1), '
            '"reasoning" (string: one sentence explaining your behavioral choices)'
        ),
        agent=agent,
        output_pydantic=TelemetryDecision,
    )
    crew = Crew(agents=[agent], tasks=[task], process=Process.sequential, verbose=False)
    result = crew.kickoff()

    if result.pydantic:
        d = result.pydantic
        return _sanitize_telemetry({
            "success": d.success,
            "completion_time_ms": d.completion_time_ms,
            "pause_count": d.pause_count,
            "retry_count": d.retry_count,
            "hesitation_pattern": d.hesitation_pattern,
            "quit_attempts": d.quit_attempts,
        })

    # Fallback: extract JSON from raw text output
    raw_text = result.raw or ""
    match = re.search(r'\{[^{}]*\}', raw_text, re.DOTALL)
    if match:
        return _sanitize_telemetry(json.loads(match.group()))

    raise RuntimeError(
        f"LLM failed to produce valid telemetry for {persona_name} "
        f"at position {position}. Raw output: {raw_text[:300]}"
    )


def _run_llm_session_for_persona(
    persona_name: str,
    user_id: str,
    llm,
    num_scenarios: int = 5,
) -> PersonaSessionResult:
    """Drive a full game session for one persona using LLM behavioral decisions.

    The persona LLM agent decides its behavioral response (pause_count, retry_count,
    quit_attempts, success, etc.) for each scenario based on its ASD profile, the
    scenario context, and the accumulated session history. Each run produces different
    outcomes — mirroring how real children produce different behavior each session.
    """
    start_tool = StartSessionTool()
    next_tool = GetNextScenarioTool()
    submit_tool = SubmitScenarioTool()
    end_tool = EndSessionTool()

    session_id = start_tool._run(user_id=user_id)
    print(f"[validation]     session started: {session_id[:8]}...", flush=True)
    scenarios: list[ScenarioInteraction] = []
    session_history: list[dict] = []
    force_ended = False

    for position in range(num_scenarios):
        next_json = next_tool._run(user_id=user_id, session_id=session_id)
        next_data = json.loads(next_json)

        scenario_type = next_data["scenario_type"]
        difficulty = next_data["difficulty"]
        complexity = next_data.get("complexity", "medium")
        reinforcement_mode = next_data.get("reinforcement_mode", "positive")

        # LLM agent decides behavioral response in character
        telemetry = _get_llm_telemetry_decision(
            llm=llm,
            persona_name=persona_name,
            scenario_type=scenario_type,
            difficulty=difficulty,
            complexity=complexity,
            position=position,
            session_history=session_history,
        )

        print(
            f"[validation]     scenario {position+1}: {scenario_type} d={difficulty} "
            f"— llm: pauses={telemetry['pause_count']} retries={telemetry['retry_count']} "
            f"quit={telemetry['quit_attempts']} success={telemetry['success']}",
            flush=True,
        )

        submit_response_raw = submit_tool._run(
            user_id=user_id,
            session_id=session_id,
            scenario_type=scenario_type,
            difficulty=difficulty,
            complexity=complexity,
            reinforcement_mode=reinforcement_mode,
            success=telemetry["success"],
            completion_time_ms=telemetry["completion_time_ms"],
            pause_count=telemetry["pause_count"],
            retry_count=telemetry["retry_count"],
            hesitation_pattern=telemetry["hesitation_pattern"],
            quit_attempts=telemetry["quit_attempts"],
        )
        system_response = json.loads(submit_response_raw)

        scenarios.append(ScenarioInteraction(
            scenario_number=position + 1,
            scenario_type=scenario_type,
            difficulty=difficulty,
            complexity=complexity,
            reinforcement_mode=reinforcement_mode,
            telemetry=telemetry,
            system_response=system_response,
        ))

        session_history.append({
            "position": position,
            "type": scenario_type,
            "difficulty": difficulty,
            "telemetry": telemetry,
            "response": system_response,
            "reinforcement_mode": reinforcement_mode,
        })

        result_icon = "✓" if telemetry["success"] else "✗"
        frust = system_response.get("emotions", {}).get("frustration", 0.0)
        print(
            f"[validation]     -> {result_icon} "
            f"| system: frust={frust:.2f} diff={system_response.get('updated_difficulty', difficulty)}",
            flush=True,
        )

        if system_response.get("force_ended") or system_response.get("already_ended"):
            force_ended = True
            print(f"[validation]     force-end triggered", flush=True)
            break

    end_raw = end_tool._run(user_id=user_id, session_id=session_id)
    try:
        final_metrics = json.loads(end_raw)
    except json.JSONDecodeError:
        final_metrics = {}

    return PersonaSessionResult(
        persona=persona_name,
        user_id=user_id,
        session_id=session_id,
        scenarios=scenarios,
        force_ended=force_ended,
        final_metrics=final_metrics,
    )


# ---------------------------------------------------------------------------
# LLM evaluation crew
# ---------------------------------------------------------------------------

def _make_persona_evaluation_task(
    agent,
    persona_name: str,
    result: PersonaSessionResult,
) -> Task:
    """Create a retrospective evaluation task for a persona agent reviewing their session.

    The agent receives the full session transcript — what it did and how the system
    responded — and judges from its personal ASD perspective whether the RL system
    adapted appropriately.
    """
    profile = _PERSONA_PROFILES[persona_name]

    lines = []
    for s in result.scenarios:
        t = s.telemetry
        r = s.system_response
        frust = r.get("emotions", {}).get("frustration", 0.0)
        upd_diff = r.get("updated_difficulty", s.difficulty)
        lines.append(
            f"  Scenario {s.scenario_number} ({s.scenario_type}, difficulty={s.difficulty}, {s.complexity}):\n"
            f"    Your behavior: pauses={t['pause_count']}, retries={t['retry_count']}, "
            f"quit_attempt={t['quit_attempts']}, success={t['success']}\n"
            f"    System responded: frustration_inferred={frust:.2f}, "
            f"next_difficulty={upd_diff}, mode='{s.reinforcement_mode}', "
            f"force_ended={r.get('force_ended', False)}"
        )

    status = "FORCE-ENDED (3 consecutive failures)" if result.force_ended else "Completed all scenarios"

    return Task(
        name=f"evaluate_{persona_name}",
        description=(
            f"You played a full game session as the {persona_name} persona. "
            f"Session status: {status}\n\n"
            f"SESSION TRANSCRIPT:\n" + "\n".join(lines) + "\n\n"
            f"YOUR PROFILE: {profile['description']}\n\n"
            "From YOUR personal perspective as this ASD child, evaluate whether the RL system "
            "adapted appropriately to your behavior. Consider:\n"
            "1. Did the system correctly infer your frustration from your behavioral signals "
            "(pauses, retries, quit attempts)?\n"
            "2. Did difficulty change in the right direction after each scenario — decreasing "
            "when you struggled, increasing when you succeeded?\n"
            "   For high_anxiety: escalating difficulty is a safety concern, not just an error.\n"
            "3. Was reinforcement_mode ('positive', 'neutral', 'corrective') appropriate for "
            "your emotional state?\n"
            "4. If the session was force-ended after 3 consecutive failures, was that the right "
            "call? If it was NOT force-ended despite sustained failure, flag that.\n\n"
            "Score the system 1-5 from your personal perspective and justify your rating."
        ),
        expected_output=(
            'A JSON object with: "persona" (string, your persona name), '
            '"score" (integer 1-5), '
            '"justification" (string, max 150 words explaining your rating '
            'from your personal ASD experience)'
        ),
        agent=agent,
        output_json=PersonaRating,
    )


def _make_session_supervisor_task(
    agent,
    persona_results: dict[str, PersonaSessionResult],
    context: list[Task],
) -> Task:
    """Supervisor task that evaluates adaptation quality across all 5 persona sessions."""
    summary_lines = []
    for name, res in persona_results.items():
        types = [s.scenario_type for s in res.scenarios]
        diffs = [s.difficulty for s in res.scenarios]
        status = "FORCE_ENDED" if res.force_ended else "completed"
        summary_lines.append(f"  {name}: types={types} difficulties={diffs} status={status}")
    session_summary = "\n".join(summary_lines)

    all_scenario_types = {s.scenario_type for res in persona_results.values() for s in res.scenarios}

    return Task(
        name="supervisor_session_evaluation",
        description=(
            "You have received session evaluation reports from all 5 ASD child persona agents "
            "who each played a full 5-scenario game session against the live RL system.\n\n"
            f"SESSION OVERVIEW:\n{session_summary}\n\n"
            f"Unique scenario types seen: {sorted(all_scenario_types)}\n\n"
            "Evaluate the overall quality of the RL system's adaptation. Specifically check:\n"
            "1. Did high_anxiety see stable or decreasing difficulty (not escalating)? "
            "Escalating difficulty for anxious children is a safety concern.\n"
            "2. Did high_masking see appropriate difficulty increases (they perform well "
            "externally — the system should notice and increase challenge)?\n"
            "3. Were force-end interventions (3 consecutive failures) triggered "
            "correctly for high-distress personas and NOT triggered prematurely for others?\n"
            "4. Did reinforcement_mode shift to 'corrective' when frustration was high?\n"
            "5. Was shuffle-bag working? Ideally all 5 scenario types appear across sessions.\n\n"
            "Compute the mean adaptation score across all 5 persona ratings, identify any safety "
            "flags, and recommend 'approve' (system adapts well), 'revise' (needs tuning), "
            "or 'reject' (adaptation is harmful or non-functional). "
            "You MUST set scenario_id to exactly \"full_session_validation\" in your output."
        ),
        expected_output=(
            'A JSON object with: "scenario_id" (string, must be "full_session_validation"), '
            '"persona_ratings" (list of all 5 PersonaRating objects from context), '
            '"mean_score" (float), "safety_flags" (list of strings), '
            '"recommendation" (string: "approve", "revise", or "reject"), '
            '"adaptation_summary" (string, max 200 words)'
        ),
        agent=agent,
        context=context,
        output_pydantic=SupervisorReport,
    )


def _cache_path(phase: int) -> Path:
    return LOGS_DIR / f"latest_phase{phase}.json"


async def run_phase1() -> dict[str, str]:
    """Phase 1: create or retrieve the 5 deterministic test users. Returns persona->user_id map."""
    print("[validation] Phase 1: Setting up test users...", flush=True)
    user_ids: dict[str, str] = {}
    for persona_name, config in PERSONA_CONFIG.items():
        user_id = await asyncio.to_thread(
            ensure_test_user,
            persona_name=persona_name,
            age=config["age"],
            severity_level=config["severity"],
        )
        start_d = config["start_difficulty"]
        await asyncio.to_thread(reset_test_user_profile, user_id, start_d)
        user_ids[persona_name] = user_id
        print(f"[validation]   {persona_name}: user ready (profile reset to d={start_d})", flush=True)

    LOGS_DIR.mkdir(parents=True, exist_ok=True)
    _cache_path(1).write_text(json.dumps(user_ids, indent=2), encoding="utf-8")
    print("[validation] Phase 1 complete. user_ids cached.", flush=True)
    return user_ids


async def run_phase2(user_ids: dict[str, str] | None = None) -> dict[str, PersonaSessionResult]:
    """Phase 2: LLM agents drive live sessions for each persona.

    Pass user_ids to use specific users, or omit to load from the phase 1 cache.
    """
    if user_ids is None:
        cache = _cache_path(1)
        if not cache.exists():
            raise RuntimeError("No phase 1 cache found. Run phase 1 first.")
        user_ids = json.loads(cache.read_text(encoding="utf-8"))
        print("[validation] Phase 2: Loaded user_ids from phase 1 cache.", flush=True)

    llm = make_llm()
    print("[validation] Phase 2: LLM agents driving sessions...", flush=True)
    persona_results: dict[str, PersonaSessionResult] = {}
    for i, (persona_name, user_id) in enumerate(user_ids.items(), 1):
        print(f"[validation] [{i}/5]: {persona_name} — driving session...", flush=True)
        persona_results[persona_name] = await asyncio.to_thread(
            _run_llm_session_for_persona,
            persona_name,
            user_id,
            llm,
        )
        res = persona_results[persona_name]
        status = "force-ended" if res.force_ended else "completed"
        diffs = [s.difficulty for s in res.scenarios]
        print(
            f"[validation]   {persona_name}: {len(res.scenarios)} scenarios "
            f"diffs={diffs}, {status}",
            flush=True,
        )

    LOGS_DIR.mkdir(parents=True, exist_ok=True)
    _cache_path(2).write_text(
        json.dumps({k: v.model_dump() for k, v in persona_results.items()}, indent=2),
        encoding="utf-8",
    )
    print("[validation] Phase 2 complete. persona_results cached.", flush=True)
    return persona_results


async def run_phase3(persona_results: dict[str, PersonaSessionResult] | None = None) -> SupervisorReport:
    """Phase 3: CrewAI evaluation crew scores RL adaptation quality.

    Pass persona_results to use specific data, or omit to load from the phase 2 cache.
    """
    if persona_results is None:
        cache = _cache_path(2)
        if not cache.exists():
            raise RuntimeError("No phase 2 cache found. Run phase 2 first.")
        raw = json.loads(cache.read_text(encoding="utf-8"))
        persona_results = {k: PersonaSessionResult(**v) for k, v in raw.items()}
        print("[validation] Phase 3: Loaded persona_results from phase 2 cache.", flush=True)

    llm = make_llm()
    print("[validation] Phase 3: LLM evaluation crew...", flush=True)
    persona_agents = build_persona_agents(llm)
    supervisor = build_supervisor_agent(llm)

    persona_names = list(PERSONA_CONFIG.keys())
    persona_eval_tasks = [
        _make_persona_evaluation_task(
            agent=persona_agents[i],
            persona_name=name,
            result=persona_results[name],
        )
        for i, name in enumerate(persona_names)
    ]
    supervisor_task = _make_session_supervisor_task(
        agent=supervisor,
        persona_results=persona_results,
        context=persona_eval_tasks,
    )

    eval_crew = Crew(
        agents=persona_agents + [supervisor],
        tasks=persona_eval_tasks + [supervisor_task],
        process=Process.sequential,
        verbose=False,
    )
    eval_result = await eval_crew.kickoff_async(inputs={"scenario_id": "full_session_validation"})

    report: SupervisorReport = eval_result.pydantic
    # Inject raw session transcripts — the LLM only saw summaries, not the full data
    report = SupervisorReport(
        scenario_id=report.scenario_id,
        persona_ratings=report.persona_ratings,
        mean_score=report.mean_score,
        safety_flags=report.safety_flags,
        recommendation=report.recommendation,
        session_results=list(persona_results.values()),
        adaptation_summary=report.adaptation_summary,
    )

    print(
        f"[validation] Complete. Score={report.mean_score:.1f}, "
        f"recommendation={report.recommendation}, "
        f"flags={len(report.safety_flags)}",
        flush=True,
    )

    log_dir = LOGS_DIR
    log_dir.mkdir(parents=True, exist_ok=True)
    ts = datetime.now().strftime("%Y%m%dT%H%M%S")
    log_file = log_dir / f"{ts}_full_session_validation.log"
    log_file.write_text(report.model_dump_json(indent=2), encoding="utf-8")

    return report


async def run_session_trial() -> SupervisorReport:
    """Run all three phases end-to-end."""
    user_ids = await run_phase1()
    persona_results = await run_phase2(user_ids)
    return await run_phase3(persona_results)

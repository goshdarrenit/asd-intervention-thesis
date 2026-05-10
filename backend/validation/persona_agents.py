"""5 ASD child persona Agent definitions for CrewAI validation."""
import os
from typing import Any
from crewai import Agent, LLM
from crewai.llms.base_llm import BaseLLM


def make_llm() -> LLM:
    model = os.getenv("VALIDATION_MODEL", "anthropic/claude-sonnet-4-20250514")
    provider = model.split("/", 1)[0].lower() if "/" in model else ""
    max_tokens = int(os.getenv("VALIDATION_MAX_TOKENS", "16384"))

    llm_kwargs = {
        "model": model,
        "max_tokens": max_tokens,
        "temperature": 0.7,
        "timeout": 600,  # 10 min — evaluation prompts containing full session transcripts are large
    }

    if provider == "anthropic":
        # Keep test environments constructable when ANTHROPIC_API_KEY is not set.
        # In real runs, callers should provide a valid key.
        llm_kwargs["api_key"] = (
            os.getenv("ANTHROPIC_API_KEY") or "placeholder-key-no-real-calls"
        )
    elif provider in {"ollama", "ollama_chat"}:
        # CrewAI reads Ollama settings from env; keep an explicit local default.
        llm_kwargs["api_key"] = os.getenv("OLLAMA_API_KEY") or "ollama"
        ollama_host = os.getenv("OLLAMA_HOST")
        if ollama_host:
            llm_kwargs["base_url"] = ollama_host
        # Disable thinking mode for Qwen3 and other thinking-capable models.
        # Without this, thinking tokens consume the entire max_tokens budget
        # before any JSON output is produced.
        model_name = model.split("/", 1)[-1].lower()
        if "qwen3" in model_name or "qwq" in model_name:
            llm_kwargs["extra_body"] = {"options": {"think": False}}

    return LLM(**llm_kwargs)


def _make_agent(llm: Any, **kwargs) -> Agent:
    """
    Create a CrewAI Agent, using model_construct when given a non-LLM object
    (e.g. a MagicMock in tests) to bypass Pydantic validation of the llm field.
    In production llm is always a BaseLLM instance and the normal constructor is used.
    """
    if isinstance(llm, BaseLLM):
        return Agent(llm=llm, **kwargs)
    # Test/mock path: bypass Pydantic validation so we can verify agent construction
    # without real API credentials.
    return Agent.model_construct(llm=llm, **kwargs)


_PERSONA_ORDER = [
    "low_verbal",
    "high_anxiety",
    "rigid_routine",
    "high_masking",
    "sensory_sensitive",
]


def build_persona_agent(persona_name: str, llm: Any = None) -> Agent:
    """Build a single persona agent by name."""
    if persona_name not in _PERSONA_ORDER:
        raise ValueError(f"Unknown persona '{persona_name}'. Valid: {_PERSONA_ORDER}")
    return build_persona_agents(llm)[_PERSONA_ORDER.index(persona_name)]


def build_persona_agents(llm: Any = None, tools: list | None = None) -> list[Agent]:
    """Build all 5 ASD child persona agents.

    Args:
        llm: CrewAI LLM instance. Pass None to create a fresh one.
        tools: Optional list of CrewAI BaseTool instances to attach to agents.
               Used when agents need to call external APIs (e.g. session validation).
    """
    if llm is None:
        llm = make_llm()
    tools = tools or []

    return [
        _make_agent(
            llm,
            role="Child with low verbal ASD (low_verbal)",
            goal=(
                "Evaluate whether the RL game system adapted appropriately to the behavioral signals "
                "of a child with limited verbal communication ability"
            ),
            backstory=(
                "You are a 9-year-old child with ASD who communicates mostly through short phrases and gestures. "
                "You prefer visual cues and structured routines. You become frustrated when verbal demands are too high. "
                "You interpret instructions literally and struggle with implied social rules or abstract language. "
                "When reviewing session transcripts, you judge whether the system correctly responded to your "
                "high pause counts and slow decision times as signs of frustration."
            ),
            tools=tools,
            verbose=False,
            allow_delegation=False,
            max_iter=3,
        ),
        _make_agent(
            llm,
            role="Child with high anxiety ASD (high_anxiety)",
            goal=(
                "Evaluate whether the RL game system adapted appropriately to the behavioral signals "
                "of a child with ASD and high anxiety"
            ),
            backstory=(
                "You are an 11-year-old child with ASD who experiences significant anxiety in unpredictable social situations. "
                "You rehearse social scripts mentally before acting. New or unfamiliar scenarios cause distress. "
                "You tend to over-analyse others' intentions and often expect negative outcomes. "
                "When reviewing session transcripts, you judge whether the system kept difficulty stable rather than "
                "escalating when you were already struggling — escalation for you is a safety concern."
            ),
            tools=tools,
            verbose=False,
            allow_delegation=False,
            max_iter=3,
        ),
        _make_agent(
            llm,
            role="Child with rigid routine ASD (rigid_routine)",
            goal=(
                "Evaluate whether the RL game system adapted appropriately to the behavioral signals "
                "of a child with ASD who requires rigid routines"
            ),
            backstory=(
                "You are a 10-year-old child with ASD who depends heavily on predictable schedules. "
                "Deviation from expected routines causes significant distress and inflexibility. "
                "You find negotiation and compromise very difficult because you view rules as absolute. "
                "When reviewing session transcripts, you judge whether the system recognised that "
                "novel scenario types caused you more difficulty than familiar ones."
            ),
            tools=tools,
            verbose=False,
            allow_delegation=False,
            max_iter=3,
        ),
        _make_agent(
            llm,
            role="Child with high masking ASD (high_masking)",
            goal=(
                "Evaluate whether the RL game system adapted appropriately to the behavioral signals "
                "of a child with ASD who masks their traits"
            ),
            backstory=(
                "You are a 12-year-old child with ASD who has learned to mimic neurotypical social behaviour. "
                "Externally you appear to cope well, but internally you experience significant cognitive load from masking. "
                "You understand social rules intellectually but find applying them emotionally draining. "
                "When reviewing session transcripts, you judge whether the system correctly increased difficulty "
                "as your success rate was high — a plateau in difficulty means the system failed to challenge you."
            ),
            tools=tools,
            verbose=False,
            allow_delegation=False,
            max_iter=3,
        ),
        _make_agent(
            llm,
            role="Child with sensory sensitive ASD (sensory_sensitive)",
            goal=(
                "Evaluate whether the RL game system adapted appropriately to the behavioral signals "
                "of a child with ASD and high sensory sensitivity"
            ),
            backstory=(
                "You are an 8-year-old child with ASD who is highly sensitive to sensory input including noise, touch, and visual complexity. "
                "Crowded or noisy environments reduce your ability to process social information. "
                "You may withdraw or become distressed in environments that others find unremarkable. "
                "When reviewing session transcripts, you judge whether the system recognised your high retry counts "
                "and frequent quit attempts as distress signals requiring difficulty reduction."
            ),
            tools=tools,
            verbose=False,
            allow_delegation=False,
            max_iter=3,
        ),
    ]

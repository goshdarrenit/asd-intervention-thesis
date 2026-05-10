"""Scenario library for the CrewAI ASD validation framework."""

PERSONA_NAMES: list[str] = [
    "low_verbal",
    "high_anxiety",
    "rigid_routine",
    "high_masking",
    "sensory_sensitive",
]

# Sentinel used when running a full live-session validation via the game API
FULL_SESSION_SCENARIO: dict = {
    "id": "full_session_validation",
    "description": "Full 5-scenario session driven by the live game session API",
    "context": "Validates RL adaptation quality across a complete session lifecycle for each persona",
}

SCENARIOS: list[dict] = [
    {
        "id": "sharing_peer_conflict",
        "description": (
            "A child is playing with their favourite toy when a peer approaches and also wants to play with it. "
            "The peer persists in requesting access to the toy. "
            "The child must decide how to respond to the peer's request without becoming dysregulated."
        ),
        "context": (
            "Setting: Classroom free-play period. Participants: One child with ASD (age 8-12) and one neurotypical peer. "
            "ASD profile tested: Ability to share objects and negotiate resource access under mild social pressure."
        ),
    },
    {
        "id": "patience_queue",
        "description": (
            "A child is waiting in the school lunch queue and must wait several minutes for their turn. "
            "The queue moves slowly and peers around them are chatting loudly. "
            "The child must maintain composure and wait without cutting in or leaving the queue."
        ),
        "context": (
            "Setting: School cafeteria lunchtime. Participants: One child with ASD (age 8-12) and surrounding peers. "
            "ASD profile tested: Ability to tolerate waiting and sensory stimulation in a structured social context."
        ),
    },
    {
        "id": "emotion_recognition_playground",
        "description": (
            "A child on the playground notices a peer who has fallen and is sitting alone. "
            "The peer's facial expression is ambiguous — it could signal distress, embarrassment, or happiness. "
            "The child must interpret the expression and decide whether to approach and offer help."
        ),
        "context": (
            "Setting: School playground during break. Participants: One child with ASD (age 8-12) and one peer. "
            "ASD profile tested: Ability to read facial emotion cues in ambiguous, real-world social situations."
        ),
    },
    {
        "id": "turn_taking_game",
        "description": (
            "A child is playing a board game with two peers and must wait for both peers to complete their turns "
            "before they can move again. One peer takes an unusually long time on their turn. "
            "The child must wait patiently without rushing the peer or abandoning the game."
        ),
        "context": (
            "Setting: Classroom game session. Participants: One child with ASD (age 8-12) and two peers. "
            "ASD profile tested: Ability to inhibit impulse to act and tolerate delay of gratification in a group game."
        ),
    },
    {
        "id": "conflict_resolution_lunchroom",
        "description": (
            "A child arrives at the lunchroom to find that another child has taken their usual seat. "
            "The other child does not acknowledge the issue, and no other preferred seats are available. "
            "The child must choose a de-escalation strategy to resolve the situation without a confrontation."
        ),
        "context": (
            "Setting: School lunchroom. Participants: One child with ASD (age 8-12) and one peer who has taken their seat. "
            "ASD profile tested: Flexibility in response to routine disruption and conflict resolution under mild social stress."
        ),
    },
]


/// Models a branching choice tree where each node presents a situation
/// and multiple choice options. Used to create narrative scenarios for
/// teaching de-escalation and cooperation skills.
library;

/// A node in the choice tree representing a situation with multiple choices
class ChoiceNode {
  /// Situation description text presented to the user
  final String prompt;

  /// List of available choices at this node
  final List<ChoiceOption> choices;

  const ChoiceNode({
    required this.prompt,
    required this.choices,
  });
}

/// A single choice option within a node
class ChoiceOption {
  /// Unique identifier for this choice
  final String id;

  /// Button label text shown to the user
  final String text;

  /// Whether this is a cooperative/de-escalation choice (for scoring)
  final bool isDeEscalation;

  /// Next node to navigate to (null = leaf/ending)
  final ChoiceNode? nextNode;

  const ChoiceOption({
    required this.id,
    required this.text,
    required this.isDeEscalation,
    this.nextNode,
  });
}

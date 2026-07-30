/// Machine-readable reasons the app is advising what it is advising.
///
/// Replaces the previous `List<String>` of prose. Consumers could not filter,
/// deduplicate, prioritise or localise a bag of sentences — the alert service
/// in particular had no way to tell "school zone ahead" from "it is raining".
enum AdvisoryCode {
  severeWeather,
  fog,
  wetRoad,
  iceRisk,
  nightDriving,
  lowSunGlare,
  lowVisibility,
  schoolZone,
  constructionZone,
  residentialArea,
  roundaboutAhead,
  junctionAhead,
  unmappedRoad,
  inferredLimit,
  stopRecommended,
}

enum AdvisorySeverity { info, caution, danger }

class Advisory {
  final AdvisoryCode code;
  final AdvisorySeverity severity;
  final String message;

  const Advisory({
    required this.code,
    required this.severity,
    required this.message,
  });

  @override
  bool operator ==(Object other) =>
      other is Advisory && other.code == code;

  @override
  int get hashCode => code.hashCode;

  @override
  String toString() => 'Advisory(${code.name}, ${severity.name}): $message';
}

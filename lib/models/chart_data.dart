class ChartData {
  final String x;
  final double completionPercent;
  final double completionVolume;
  final DateTime date;

  var timestamp;
  ChartData(
    this.x,
    this.completionPercent,
    this.completionVolume,
    this.date,
  );
}

double clampSliderValue(double value, double max) {
  if (max.isNaN || max.isInfinite || max <= 0) {
    return 0.0;
  }
  if (value.isNaN || value.isInfinite) {
    return 0.0;
  }
  if (value < 0) {
    return 0.0;
  }
  if (value > max) {
    return max;
  }
  return value;
}

double sliderMaxFromDuration(Duration duration) {
  final max = duration.inMilliseconds.toDouble();
  return max > 0 ? max : 1.0;
}

import 'dart:async';

// كلاس لتخزين BPM وحالة الحركة
class BPMWithMovement {
  final int bpm;
  final String movementStatus;

  BPMWithMovement({required this.bpm, required this.movementStatus});
}

final StreamController<BPMWithMovement> bpmStreamController = StreamController<BPMWithMovement>.broadcast();

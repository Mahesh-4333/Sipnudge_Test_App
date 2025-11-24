import 'package:flutter/material.dart';
import 'package:equatable/equatable.dart';

/// Represents the completion status of a hydration slot.
enum HydrationStatus { pending, completed }

/// Represents the different hydration slots during the day.
enum HydrationSlot {
  wakeup,
  breakfast,
  midMorning,
  lunch,
  midAfternoon,
  evening,
  afterDinner,
}

/// Extension methods for `HydrationSlot` to get labels and percentages.
extension HydrationSlotX on HydrationSlot {
  /// Human-readable label for each hydration slot.
  String get label {
    switch (this) {
      case HydrationSlot.wakeup:
        return 'Wakeup Time';
      case HydrationSlot.breakfast:
        return 'Breakfast Time';
      case HydrationSlot.midMorning:
        return 'Mid-Morning';
      case HydrationSlot.lunch:
        return 'Lunch Time';
      case HydrationSlot.midAfternoon:
        return 'Mid-Afternoon';
      case HydrationSlot.evening:
        return 'Evening';
      case HydrationSlot.afterDinner:
        return 'After Dinner';
    }
  }

  /// Percentage of daily hydration goal this slot represents.
  double get percentage {
    switch (this) {
      case HydrationSlot.wakeup:
        return 0.25; // 25%
      default:
        return 0.125; // 12.5%
    }
  }
}

/// Represents a single hydration entry for a time slot.
class HydrationEntry extends Equatable {
  final HydrationSlot slot;
  final TimeOfDay startTime;
  final TimeOfDay endTime;
  // final double amount; // old variable Target amount (mL)
  final double targetIntake; // Target amount (mL)
  final double waterDrank; // Actual water consumed (mL)
  final HydrationStatus status;

  const HydrationEntry({
    required this.slot,
    required this.startTime,
    required this.endTime,
    // required this.amount,
    required this.targetIntake,
    this.waterDrank = 0.0,
    this.status = HydrationStatus.pending,
  });

  HydrationEntry copyWith({
    HydrationSlot? slot,
    TimeOfDay? startTime,
    TimeOfDay? endTime,
    double? amount,
    double? targetIntake,
    double? waterDrank,
    HydrationStatus? status,
  }) {
    return HydrationEntry(
      slot: slot ?? this.slot,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      // amount: amount ?? this.amount,
      targetIntake: targetIntake ?? this.targetIntake,
      waterDrank: waterDrank ?? this.waterDrank,
      status: status ?? this.status,
    );
  }

  String get formattedRange =>
      "${_formatTime(startTime)} - ${_formatTime(endTime)}";

  static String _formatTime(TimeOfDay time) {
    final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.period == DayPeriod.am ? "AM" : "PM";
    return "$hour:$minute $period";
  }

  @override
  List<Object> get props =>
      [slot, startTime, endTime, targetIntake, waterDrank, status];
}

/// Represents a time range in the day.
class TimeOfDayRange {
  final TimeOfDay start;
  final TimeOfDay end;

  const TimeOfDayRange({required this.start, required this.end});
}

//=================================================================

// import 'package:flutter/material.dart';
// import 'package:equatable/equatable.dart';

// /// Represents the completion status of a hydration slot.
// enum HydrationStatus { pending, completed }

// /// Represents the different hydration slots during the day.
// enum HydrationSlot {
//   wakeup,
//   breakfast,
//   midMorning,
//   lunch,
//   midAfternoon,
//   evening,
//   afterDinner,
// }

// /// Extension methods for `HydrationSlot` to get labels and percentages.
// extension HydrationSlotX on HydrationSlot {
//   /// Human-readable label for each hydration slot.
//   String get label {
//     switch (this) {
//       case HydrationSlot.wakeup:
//         return 'Wakeup Time';
//       case HydrationSlot.breakfast:
//         return 'Breakfast Time';
//       case HydrationSlot.midMorning:
//         return 'Mid-Morning';
//       case HydrationSlot.lunch:
//         return 'Lunch Time';
//       case HydrationSlot.midAfternoon:
//         return 'Mid-Afternoon';
//       case HydrationSlot.evening:
//         return 'Evening';
//       case HydrationSlot.afterDinner:
//         return 'After Dinner';
//     }
//   }

//   /// Percentage of daily hydration goal this slot represents.
//   double get percentage {
//     switch (this) {
//       case HydrationSlot.wakeup:
//         return 0.25; // 25%
//       default:
//         return 0.125; // 12.5%
//     }
//   }
// }

// /// Represents a single hydration entry for a time slot.
// class HydrationEntry extends Equatable {
//   final HydrationSlot slot;
//   final TimeOfDay startTime;
//   final TimeOfDay endTime;
//   final double amount; // Target amount (mL)
//   final double targetIntake;
//   final double waterDrank; // Actual water consumed (mL)
//   final HydrationStatus status;

//   const HydrationEntry({
//     required this.slot,
//     required this.startTime,
//     required this.endTime,
//     required this.amount,
//     required this.targetIntake,
//     this.waterDrank = 0.0,
//     this.status = HydrationStatus.pending,
//   });

//   HydrationEntry copyWith({
//     HydrationSlot? slot,
//     TimeOfDay? startTime,
//     TimeOfDay? endTime,
//     double? amount,
//     double? targetIntake,
//     double? waterDrank,
//     HydrationStatus? status,
//   }) {
//     return HydrationEntry(
//       slot: slot ?? this.slot,
//       startTime: startTime ?? this.startTime,
//       endTime: endTime ?? this.endTime,
//       amount: amount ?? this.amount,
//       targetIntake: targetIntake ?? this.targetIntake,
//       waterDrank: waterDrank ?? this.waterDrank,
//       status: status ?? this.status,
//     );
//   }

//   String get formattedRange =>
//       "${_formatTime(startTime)} - ${_formatTime(endTime)}";

//   static String _formatTime(TimeOfDay time) {
//     final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
//     final minute = time.minute.toString().padLeft(2, '0');
//     final period = time.period == DayPeriod.am ? "AM" : "PM";
//     return "$hour:$minute $period";
//   }

//   @override
//   List<Object> get props =>
//       [slot, startTime, endTime, amount, waterDrank, status];
// }

// /// Represents a time range in the day.
// class TimeOfDayRange {
//   final TimeOfDay start;
//   final TimeOfDay end;

//   const TimeOfDayRange({required this.start, required this.end});
// }

//=================================================================

// // models/hydration_entry.dart
// import 'package:flutter/material.dart';
// import 'package:equatable/equatable.dart';

// /// Represents the completion status of a hydration slot.
// enum HydrationStatus { pending, completed }

// /// The different hydration slots.
// enum HydrationSlot {
//   wakeup,
//   breakfast,
//   midMorning,
//   lunch,
//   midAfternoon,
//   evening,
//   afterDinner,
// }

// extension HydrationSlotX on HydrationSlot {
//   String get label {
//     switch (this) {
//       case HydrationSlot.wakeup:
//         return 'Wakeup Time';
//       case HydrationSlot.breakfast:
//         return 'Breakfast Time';
//       case HydrationSlot.midMorning:
//         return 'Mid-Morning';
//       case HydrationSlot.lunch:
//         return 'Lunch Time';
//       case HydrationSlot.midAfternoon:
//         return 'Mid-Afternoon';
//       case HydrationSlot.evening:
//         return 'Evening';
//       case HydrationSlot.afterDinner:
//         return 'After Dinner';
//     }
//   }

//   double get percentage {
//     switch (this) {
//       case HydrationSlot.wakeup:
//         return 0.25; // 25%
//       default:
//         return 0.125; // 12.5%
//     }
//   }
// }

// /// HydrationEntry with explicit `targetIntake` field (in mL).
// class HydrationEntry extends Equatable {
//   final HydrationSlot slot;
//   final TimeOfDay startTime;
//   final TimeOfDay endTime;
//   final double amount; // legacy field if you still need it
//   final double targetIntake; // target mL (device's planned amount)
//   final double waterDrank; // actual consumed mL
//   final HydrationStatus status;

//   const HydrationEntry({
//     required this.slot,
//     required this.startTime,
//     required this.endTime,
//     required this.amount,
//     required this.targetIntake,
//     required this.waterDrank,
//     this.status = HydrationStatus.pending,
//   });

//   HydrationEntry copyWith({
//     HydrationSlot? slot,
//     TimeOfDay? startTime,
//     TimeOfDay? endTime,
//     double? amount,
//     double? targetIntake,
//     double? waterDrank,
//     HydrationStatus? status,
//   }) {
//     return HydrationEntry(
//       slot: slot ?? this.slot,
//       startTime: startTime ?? this.startTime,
//       endTime: endTime ?? this.endTime,
//       amount: amount ?? this.amount,
//       targetIntake: targetIntake ?? this.targetIntake,
//       waterDrank: waterDrank ?? this.waterDrank,
//       status: status ?? this.status,
//     );
//   }

//   String get formattedRange =>
//       "${_formatTime(startTime)} - ${_formatTime(endTime)}";

//   static String _formatTime(TimeOfDay time) {
//     final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
//     final minute = time.minute.toString().padLeft(2, '0');
//     final period = time.period == DayPeriod.am ? "AM" : "PM";
//     return "$hour:$minute $period";
//   }

//   @override
//   List<Object> get props =>
//       [slot, startTime, endTime, targetIntake, waterDrank, status];
// }

// /// Represents a time range in the day.
// class TimeOfDayRange {
//   final TimeOfDay start;
//   final TimeOfDay end;

//   const TimeOfDayRange({required this.start, required this.end});
// }

//=================================================================

// import 'package:flutter/material.dart';
// import 'package:equatable/equatable.dart';

// /// Represents the completion status of a hydration slot.
// enum HydrationStatus { pending, completed }

// /// Represents the different hydration slots during the day.
// enum HydrationSlot {
//   wakeup,
//   breakfast,
//   midMorning,
//   lunch,
//   midAfternoon,
//   evening,
//   afterDinner,
// }

// /// Extension methods for `HydrationSlot` to get labels and percentages.
// extension HydrationSlotX on HydrationSlot {
//   String get label {
//     switch (this) {
//       case HydrationSlot.wakeup:
//         return 'Wakeup Time';
//       case HydrationSlot.breakfast:
//         return 'Breakfast Time';
//       case HydrationSlot.midMorning:
//         return 'Mid-Morning';
//       case HydrationSlot.lunch:
//         return 'Lunch Time';
//       case HydrationSlot.midAfternoon:
//         return 'Mid-Afternoon';
//       case HydrationSlot.evening:
//         return 'Evening';
//       case HydrationSlot.afterDinner:
//         return 'After Dinner';
//     }
//   }

//   double get percentage {
//     switch (this) {
//       case HydrationSlot.wakeup:
//         return 0.25; // 25%
//       default:
//         return 0.125; // 12.5%
//     }
//   }
// }

// /// Represents a single hydration entry for a time slot.
// class HydrationEntry extends Equatable {
//   final HydrationSlot slot;
//   final TimeOfDay startTime;
//   final TimeOfDay endTime;
//   final double amount; //old
//   final double targetIntake; // ✅ renamed from amount
//   final double waterDrank; // Actual consumed (mL)
//   final HydrationStatus status;

//   const HydrationEntry({
//     required this.slot,
//     required this.startTime,
//     required this.endTime,
//     required this.amount,
//     required this.targetIntake,
//     this.waterDrank = 0.0,
//     this.status = HydrationStatus.pending,
//   });

//   HydrationEntry copyWith({
//     HydrationSlot? slot,
//     TimeOfDay? startTime,
//     TimeOfDay? endTime,
//     double? amount,
//     double? targetIntake,
//     double? waterDrank,
//     HydrationStatus? status,
//   }) {
//     return HydrationEntry(
//       slot: slot ?? this.slot,
//       startTime: startTime ?? this.startTime,
//       endTime: endTime ?? this.endTime,
//       amount: amount ?? this.amount,
//       targetIntake: targetIntake ?? this.targetIntake,
//       waterDrank: waterDrank ?? this.waterDrank,
//       status: status ?? this.status,
//     );
//   }

//   String get formattedRange =>
//       "${_formatTime(startTime)} - ${_formatTime(endTime)}";

//   static String _formatTime(TimeOfDay time) {
//     final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
//     final minute = time.minute.toString().padLeft(2, '0');
//     final period = time.period == DayPeriod.am ? "AM" : "PM";
//     return "$hour:$minute $period";
//   }

//   @override
//   List<Object> get props =>
//       [slot, startTime, endTime, targetIntake, waterDrank, status];
// }

// /// Represents a time range in the day.
// class TimeOfDayRange {
//   final TimeOfDay start;
//   final TimeOfDay end;

//   const TimeOfDayRange({required this.start, required this.end});
// }
// // -----------------------------------------------------------------------------
// // import 'package:flutter/material.dart';
// // import 'package:equatable/equatable.dart';

// // /// Represents the completion status of a hydration slot.
// // enum HydrationStatus { pending, completed }

// // /// Represents the different hydration slots during the day.
// // enum HydrationSlot {
// //   wakeup,
// //   breakfast,
// //   midMorning,
// //   lunch,
// //   midAfternoon,
// //   evening,
// //   afterDinner,
// // }

// // /// Extension methods for `HydrationSlot` to get labels and percentages.
// // extension HydrationSlotX on HydrationSlot {
// //   /// Human-readable label for each hydration slot.
// //   String get label {
// //     switch (this) {
// //       case HydrationSlot.wakeup:
// //         return 'Wakeup Time';
// //       case HydrationSlot.breakfast:
// //         return 'Breakfast Time';
// //       case HydrationSlot.midMorning:
// //         return 'Mid-Morning';
// //       case HydrationSlot.lunch:
// //         return 'Lunch Time';
// //       case HydrationSlot.midAfternoon:
// //         return 'Mid-Afternoon';
// //       case HydrationSlot.evening:
// //         return 'Evening';
// //       case HydrationSlot.afterDinner:
// //         return 'After Dinner';
// //     }
// //   }

// //   /// Percentage of daily hydration goal this slot represents.
// //   double get percentage {
// //     switch (this) {
// //       case HydrationSlot.wakeup:
// //         return 0.25; // 25%
// //       default:
// //         return 0.125; // 12.5%
// //     }
// //   }
// // }

// // /// Represents a single hydration entry for a time slot.
// // class HydrationEntry extends Equatable {
// //   final HydrationSlot slot;
// //   final TimeOfDay startTime;
// //   final TimeOfDay endTime;
// //   final double amount; // Target amount (mL)
// //   final double targetIntake;
// //   final double waterDrank; // Actual water consumed (mL)
// //   final HydrationStatus status;

// //   const HydrationEntry({
// //     required this.slot,
// //     required this.startTime,
// //     required this.endTime,
// //     required this.amount,
// //     required this.targetIntake,
// //     this.waterDrank = 0.0,
// //     this.status = HydrationStatus.pending,
// //   });

// //   HydrationEntry copyWith({
// //     HydrationSlot? slot,
// //     TimeOfDay? startTime,
// //     TimeOfDay? endTime,
// //     double? amount,
// //     double? targetIntake,
// //     double? waterDrank,
// //     HydrationStatus? status,
// //   }) {
// //     return HydrationEntry(
// //       slot: slot ?? this.slot,
// //       startTime: startTime ?? this.startTime,
// //       endTime: endTime ?? this.endTime,
// //       amount: amount ?? this.amount,
// //       targetIntake: targetIntake ?? this.targetIntake,
// //       waterDrank: waterDrank ?? this.waterDrank,
// //       status: status ?? this.status,
// //     );
// //   }

// //   String get formattedRange =>
// //       "${_formatTime(startTime)} - ${_formatTime(endTime)}";

// //   static String _formatTime(TimeOfDay time) {
// //     final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
// //     final minute = time.minute.toString().padLeft(2, '0');
// //     final period = time.period == DayPeriod.am ? "AM" : "PM";
// //     return "$hour:$minute $period";
// //   }

// //   @override
// //   List<Object> get props =>
// //       [slot, startTime, endTime, targetIntake, waterDrank, status];
// // }

// // /// Represents a time range in the day.
// // class TimeOfDayRange {
// //   final TimeOfDay start;
// //   final TimeOfDay end;

// //   const TimeOfDayRange({required this.start, required this.end});
// // }

// // // -----------------------------------------------------------------------------

// import 'package:flutter/material.dart';

// enum HydrationStatus { completed, pending }

// enum HydrationSlot {
//   wakeup,
//   breakfast,
//   midMorning,
//   lunch,
//   midAfternoon,
//   evening,
//   afterDinner,
// }

// extension HydrationSlotX on HydrationSlot {
//   String get label {
//     switch (this) {
//       case HydrationSlot.wakeup:
//         return 'Wakeup Time';
//       case HydrationSlot.breakfast:
//         return 'Breakfast Time';
//       case HydrationSlot.midMorning:
//         return 'Mid-Morning';
//       case HydrationSlot.lunch:
//         return 'Lunch Time';
//       case HydrationSlot.midAfternoon:
//         return 'Mid-Afternoon';
//       case HydrationSlot.evening:
//         return 'Evening';
//       case HydrationSlot.afterDinner:
//         return 'After Dinner';
//     }
//   }

//   /// 💧 Each slot's percentage of total daily goal
//   double get percentage {
//     switch (this) {
//       case HydrationSlot.wakeup:
//         return 0.25; // 25%
//       default:
//         return 0.125; // 12.5%
//     }
//   }
// }

// class HydrationEntry {
//   final HydrationSlot slot;
//   final TimeOfDay startTime;
//   final TimeOfDay endTime;
//   final double amount; // ✅ changed from int → double
//   final HydrationStatus status;
//   final double waterDrank; // ✅ changed from int → double

//   HydrationEntry({
//     required this.slot,
//     required this.startTime,
//     required this.endTime,
//     required this.amount,
//     this.waterDrank = 0.0, // ✅ default double
//     this.status = HydrationStatus.pending,
//   });

//   HydrationEntry copyWith({
//     HydrationSlot? slot,
//     TimeOfDay? startTime,
//     TimeOfDay? endTime,
//     double? amount, // ✅ changed to double
//     HydrationStatus? status,
//     double? waterDrank, // ✅ changed to double
//   }) {
//     return HydrationEntry(
//       slot: slot ?? this.slot,
//       startTime: startTime ?? this.startTime,
//       endTime: endTime ?? this.endTime,
//       amount: amount ?? this.amount,
//       status: status ?? this.status,
//       waterDrank: waterDrank ?? this.waterDrank,
//     );
//   }

//   /// Format for displaying to user: "7:30 AM - 8:30 AM"
//   String get formattedRange {
//     return "${_formatTime(startTime)} - ${_formatTime(endTime)}";
//   }

//   static String _formatTime(TimeOfDay time) {
//     final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
//     final minute = time.minute.toString().padLeft(2, '0');
//     final period = time.period == DayPeriod.am ? "AM" : "PM";
//     return "$hour:$minute $period";
//   }
// }

// class TimeOfDayRange {
//   final TimeOfDay start;
//   final TimeOfDay end;
//   TimeOfDayRange({required this.start, required this.end});
// }

// // // -----------------------------------------------------------------------------

// // // import 'package:flutter/material.dart';

// // // enum HydrationStatus { completed, pending }

// // // enum HydrationSlot {
// // //   wakeup,
// // //   breakfast,
// // //   midMorning,
// // //   lunch,
// // //   midAfternoon,
// // //   evening,
// // //   afterDinner,
// // // }

// // // extension HydrationSlotX on HydrationSlot {
// // //   String get label {
// // //     switch (this) {
// // //       case HydrationSlot.wakeup:
// // //         return 'Wakeup Time';
// // //       case HydrationSlot.breakfast:
// // //         return 'Breakfast Time';
// // //       case HydrationSlot.midMorning:
// // //         return 'Mid-Morning';
// // //       case HydrationSlot.lunch:
// // //         return 'Lunch Time';
// // //       case HydrationSlot.midAfternoon:
// // //         return 'Mid-Afternoon';
// // //       case HydrationSlot.evening:
// // //         return 'Evening';
// // //       case HydrationSlot.afterDinner:
// // //         return 'After Dinner';
// // //     }
// // //   }
// // // }

// // // class HydrationEntry {
// // //   final HydrationSlot slot;
// // //   final TimeOfDay startTime;
// // //   final TimeOfDay endTime;
// // //   final int amount;
// // //   final HydrationStatus status;
// // //   final int waterDrank;

// // //   HydrationEntry({
// // //     required this.slot,
// // //     required this.startTime,
// // //     required this.endTime,
// // //     required this.amount,
// // //     this.waterDrank = 0,
// // //     this.status = HydrationStatus.pending,
// // //   });

// // //   HydrationEntry copyWith({
// // //     HydrationSlot? slot,
// // //     TimeOfDay? startTime,
// // //     TimeOfDay? endTime,
// // //     int? amount,
// // //     HydrationStatus? status,
// // //     int? waterDrank,
// // //   }) {
// // //     return HydrationEntry(
// // //       slot: slot ?? this.slot,
// // //       startTime: startTime ?? this.startTime,
// // //       endTime: endTime ?? this.endTime,
// // //       amount: amount ?? this.amount,
// // //       status: status ?? this.status,
// // //       waterDrank: waterDrank ?? this.waterDrank,
// // //     );
// // //   }

// // //   /// Format for displaying to user: "7:30 AM - 8:30 AM"
// // //   String get formattedRange {
// // //     return "${_formatTime(startTime)} - ${_formatTime(endTime)}";
// // //   }

// // //   static String _formatTime(TimeOfDay time) {
// // //     final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
// // //     final minute = time.minute.toString().padLeft(2, '0');
// // //     final period = time.period == DayPeriod.am ? "AM" : "PM";
// // //     return "$hour:$minute $period";
// // //   }
// // // }

// // // class TimeOfDayRange {
// // //   final TimeOfDay start;
// // //   final TimeOfDay end;
// // //   TimeOfDayRange({required this.start, required this.end});
// // // }

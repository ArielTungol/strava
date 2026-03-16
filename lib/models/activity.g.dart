// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'activity.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ActivityAdapter extends TypeAdapter<Activity> {
  @override
  final int typeId = 1;

  @override
  Activity read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Activity(
      id: fields[0] as String,
      name: fields[1] as String,
      description: fields[2] as String,
      startTime: fields[3] as DateTime,
      endTime: fields[4] as DateTime?,
      distance: fields[5] as double,
      duration: fields[6] as double,
      averageSpeed: fields[7] as double,
      maxSpeed: fields[8] as double?,
      elevationGain: fields[9] as double?,
      caloriesBurned: fields[10] as int,
      routePoints: (fields[11] as List).cast<RoutePoint>(),
      type: fields[12] as ActivityType,
      averageHeartRate: fields[13] as double?,
      maxHeartRate: fields[14] as double?,
      photoUrl: fields[15] as String?,
      kudos: fields[16] as int,
      comments: (fields[17] as List).cast<String>(),
      isPrivate: fields[18] as bool,
      gearId: fields[19] as String?,
      achievementCount: fields[20] as int,
    );
  }

  @override
  void write(BinaryWriter writer, Activity obj) {
    writer
      ..writeByte(21)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.description)
      ..writeByte(3)
      ..write(obj.startTime)
      ..writeByte(4)
      ..write(obj.endTime)
      ..writeByte(5)
      ..write(obj.distance)
      ..writeByte(6)
      ..write(obj.duration)
      ..writeByte(7)
      ..write(obj.averageSpeed)
      ..writeByte(8)
      ..write(obj.maxSpeed)
      ..writeByte(9)
      ..write(obj.elevationGain)
      ..writeByte(10)
      ..write(obj.caloriesBurned)
      ..writeByte(11)
      ..write(obj.routePoints)
      ..writeByte(12)
      ..write(obj.type)
      ..writeByte(13)
      ..write(obj.averageHeartRate)
      ..writeByte(14)
      ..write(obj.maxHeartRate)
      ..writeByte(15)
      ..write(obj.photoUrl)
      ..writeByte(16)
      ..write(obj.kudos)
      ..writeByte(17)
      ..write(obj.comments)
      ..writeByte(18)
      ..write(obj.isPrivate)
      ..writeByte(19)
      ..write(obj.gearId)
      ..writeByte(20)
      ..write(obj.achievementCount);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ActivityAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class ActivityTypeAdapter extends TypeAdapter<ActivityType> {
  @override
  final int typeId = 0;

  @override
  ActivityType read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return ActivityType.running;
      case 1:
        return ActivityType.walking;
      case 2:
        return ActivityType.cycling;
      case 3:
        return ActivityType.hiking;
      case 4:
        return ActivityType.swimming;
      case 5:
        return ActivityType.workout;
      default:
        return ActivityType.running;
    }
  }

  @override
  void write(BinaryWriter writer, ActivityType obj) {
    switch (obj) {
      case ActivityType.running:
        writer.writeByte(0);
        break;
      case ActivityType.walking:
        writer.writeByte(1);
        break;
      case ActivityType.cycling:
        writer.writeByte(2);
        break;
      case ActivityType.hiking:
        writer.writeByte(3);
        break;
      case ActivityType.swimming:
        writer.writeByte(4);
        break;
      case ActivityType.workout:
        writer.writeByte(5);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ActivityTypeAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

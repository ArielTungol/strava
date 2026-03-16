// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class UserAdapter extends TypeAdapter<User> {
  @override
  final int typeId = 3;

  @override
  User read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return User(
      id: fields[0] as String,
      email: fields[1] as String,
      username: fields[2] as String,
      displayName: fields[3] as String,
      photoUrl: fields[4] as String?,
      bio: fields[5] as String?,
      location: fields[6] as String?,
      memberSince: fields[7] as DateTime,
      followers: fields[8] as int,
      following: fields[9] as int,
      totalActivities: fields[10] as int,
      totalDistance: fields[11] as double,
      totalDuration: fields[12] as int,
      totalElevation: fields[13] as int,
      achievements: (fields[14] as List).cast<String>(),
      gear: (fields[15] as List).cast<String>(),
      weeklyStats: (fields[16] as Map).cast<String, dynamic>(),
      monthlyStats: (fields[17] as Map).cast<String, dynamic>(),
      yearlyStats: (fields[18] as Map).cast<String, dynamic>(),
      isPro: fields[19] as bool,
      isVerified: fields[20] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, User obj) {
    writer
      ..writeByte(21)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.email)
      ..writeByte(2)
      ..write(obj.username)
      ..writeByte(3)
      ..write(obj.displayName)
      ..writeByte(4)
      ..write(obj.photoUrl)
      ..writeByte(5)
      ..write(obj.bio)
      ..writeByte(6)
      ..write(obj.location)
      ..writeByte(7)
      ..write(obj.memberSince)
      ..writeByte(8)
      ..write(obj.followers)
      ..writeByte(9)
      ..write(obj.following)
      ..writeByte(10)
      ..write(obj.totalActivities)
      ..writeByte(11)
      ..write(obj.totalDistance)
      ..writeByte(12)
      ..write(obj.totalDuration)
      ..writeByte(13)
      ..write(obj.totalElevation)
      ..writeByte(14)
      ..write(obj.achievements)
      ..writeByte(15)
      ..write(obj.gear)
      ..writeByte(16)
      ..write(obj.weeklyStats)
      ..writeByte(17)
      ..write(obj.monthlyStats)
      ..writeByte(18)
      ..write(obj.yearlyStats)
      ..writeByte(19)
      ..write(obj.isPro)
      ..writeByte(20)
      ..write(obj.isVerified);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

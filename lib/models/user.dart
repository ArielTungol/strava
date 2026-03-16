import 'package:equatable/equatable.dart';
import 'package:hive/hive.dart';

part 'user.g.dart';

@HiveType(typeId: 3)
class User extends Equatable {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String email;

  @HiveField(2)
  final String username;

  @HiveField(3)
  final String displayName;

  @HiveField(4)
  final String? photoUrl;

  @HiveField(5)
  final String? bio;

  @HiveField(6)
  final String? location;

  @HiveField(7)
  final DateTime memberSince;

  @HiveField(8)
  final int followers;

  @HiveField(9)
  final int following;

  @HiveField(10)
  final int totalActivities;

  @HiveField(11)
  final double totalDistance;

  @HiveField(12)
  final int totalDuration;

  @HiveField(13)
  final int totalElevation;

  @HiveField(14)
  final List<String> achievements;

  @HiveField(15)
  final List<String> gear;

  @HiveField(16)
  final Map<String, dynamic> weeklyStats;

  @HiveField(17)
  final Map<String, dynamic> monthlyStats;

  @HiveField(18)
  final Map<String, dynamic> yearlyStats;

  @HiveField(19)
  final bool isPro;

  @HiveField(20)
  final bool isVerified;

  const User({
    required this.id,
    required this.email,
    required this.username,
    required this.displayName,
    this.photoUrl,
    this.bio,
    this.location,
    required this.memberSince,
    this.followers = 0,
    this.following = 0,
    this.totalActivities = 0,
    this.totalDistance = 0,
    this.totalDuration = 0,
    this.totalElevation = 0,
    this.achievements = const [],
    this.gear = const [],
    this.weeklyStats = const {},
    this.monthlyStats = const {},
    this.yearlyStats = const {},
    this.isPro = false,
    this.isVerified = false,
  });

  String get formattedTotalDistance {
    if (totalDistance < 1000) return '${totalDistance.toStringAsFixed(0)}m';
    return '${(totalDistance / 1000).toStringAsFixed(1)}km';
  }

  User copyWith({
    String? id,
    String? email,
    String? username,
    String? displayName,
    String? photoUrl,
    String? bio,
    String? location,
    DateTime? memberSince,
    int? followers,
    int? following,
    int? totalActivities,
    double? totalDistance,
    int? totalDuration,
    int? totalElevation,
    List<String>? achievements,
    List<String>? gear,
    Map<String, dynamic>? weeklyStats,
    Map<String, dynamic>? monthlyStats,
    Map<String, dynamic>? yearlyStats,
    bool? isPro,
    bool? isVerified,
  }) {
    return User(
      id: id ?? this.id,
      email: email ?? this.email,
      username: username ?? this.username,
      displayName: displayName ?? this.displayName,
      photoUrl: photoUrl ?? this.photoUrl,
      bio: bio ?? this.bio,
      location: location ?? this.location,
      memberSince: memberSince ?? this.memberSince,
      followers: followers ?? this.followers,
      following: following ?? this.following,
      totalActivities: totalActivities ?? this.totalActivities,
      totalDistance: totalDistance ?? this.totalDistance,
      totalDuration: totalDuration ?? this.totalDuration,
      totalElevation: totalElevation ?? this.totalElevation,
      achievements: achievements ?? this.achievements,
      gear: gear ?? this.gear,
      weeklyStats: weeklyStats ?? this.weeklyStats,
      monthlyStats: monthlyStats ?? this.monthlyStats,
      yearlyStats: yearlyStats ?? this.yearlyStats,
      isPro: isPro ?? this.isPro,
      isVerified: isVerified ?? this.isVerified,
    );
  }

  @override
  List<Object?> get props => [
    id, email, username, displayName, photoUrl, bio, location,
    memberSince, followers, following, totalActivities, totalDistance,
    totalDuration, totalElevation, achievements, gear, isPro, isVerified
  ];
}
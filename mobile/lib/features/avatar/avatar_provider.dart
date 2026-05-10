import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kAvatarKey = 'selected_avatar';

/// Default avatar key used when no preference is stored.
const defaultAvatarKey = 'avatar_boy_A_1';

/// All available avatar asset keys.
const avatarKeys = [
  'avatar_boy_A_1',
  'avatar_boy_B_1',
  'avatar_girl_A_1',
  'avatar_girl_B_1',
];

/// Returns the Flutter asset path for a given avatar key.
String avatarAssetPath(String key) => 'lib/assets/avatar/$key.png';

class AvatarNotifier extends AsyncNotifier<String> {
  @override
  Future<String> build() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kAvatarKey) ?? defaultAvatarKey;
  }

  Future<void> setAvatar(String key) async {
    state = AsyncValue.data(key);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAvatarKey, key);
  }
}

final avatarProvider =
    AsyncNotifierProvider<AvatarNotifier, String>(AvatarNotifier.new);

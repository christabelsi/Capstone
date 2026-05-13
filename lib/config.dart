
class SupabaseConfig {
  SupabaseConfig._();

  static const String url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://wfgjomqbwmqfokytckmc.supabase.co',
  );

  static const String anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue:
        'sb_publishable_XU446e27UQD7LGM_OalL_g_HIm6cyWU',
  );

  static const String grantFilesBucket = 'grant-files';
}

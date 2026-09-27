/// Compiled-in Supabase connection for the NeverWin project.
///
/// The publishable key is safe to embed in client apps (Supabase docs:
/// "Publishable keys can be safely shared publicly") — RLS + SECURITY
/// DEFINER RPCs enforce all money rules server-side. The SECRET key is
/// NEVER stored here or in the repo (server/components only).
/// Users can override both values in Settings → Server.
class SupabaseDefaults {
  static const String url = 'https://ditgqxuliroodvfnlshl.supabase.co';
  static const String publishableKey =
      'sb_publishable_Mmuu9vKRWJbkjE4M9Cf52w_jy3opRdM';
}

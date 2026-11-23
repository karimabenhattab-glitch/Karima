// Eintragen aus Supabase: Project Settings > API.
// Der anon public key ist für den Browser gedacht und darf hier stehen,
// weil die Zugriffsregeln in schema.sql die Daten schützen.
// Niemals den service_role key hier eintragen oder weitergeben.
window.APP_CONFIG = {
  SUPABASE_URL: "",
  SUPABASE_ANON_KEY: ""
};

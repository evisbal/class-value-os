// Class Value OS — Supabase connection config.
//
// Fill these in from your Supabase project: Project Settings → API.
//   url     -> "Project URL"          e.g. "https://xxxxxxxxxxxx.supabase.co"
//   anonKey -> "anon" "public" key    (NOT the service_role key — never put that in client code)
//
// The anon key is safe to expose in a public static site: it can only do what your
// Row Level Security policies allow (see supabase/schema.sql). Leave both blank and
// the app will run with Demand Management showing a "not connected" state instead
// of failing.
window.SUPABASE_CONFIG = {
  url: 'https://vqdryzwudpcilhyusorz.supabase.co/rest/v1/',
  anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZxZHJ5end1ZHBjaWxoeXVzb3J6Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODY5NzQyMDMsImV4cCI6MjEwMjU1MDIwM30.t8fuwXIA08-xFK7EUozZbZG0z3Q_BEy2-351WY8jwGc'
};

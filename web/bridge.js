// Supabase bridge for Coastal Stroll — loaded by the export head_include (after the
// supabase-js UMD bundle). GDScript talks to this via JavaScriptBridge: it polls
// window.__gogi for {ready, uid, state, places}, and calls window.gogiSave / gogiDiscover.
//
// Auth: a deterministic per-user account (created server-side) is signed in here, with no
// login screen, so the save survives a refresh AND a fresh session. supabase-js persists the
// session in localStorage. The anon key below is the project's PUBLISHABLE key (safe to ship).
(function () {
  "use strict";
  var SUPABASE_URL = "https://xhhmxabftbyxrirvvihn.supabase.co";
  var SUPABASE_ANON_KEY = "sb_publishable_NZHoIxqqpSvVBP8MrLHCYA_gmg1AbN-";
  var EMAIL = "save_nmexs7bytxq2awkdnefewra3p0t1@coastal-stroll.app";
  var PASSWORD = "cstroll_NMexs7BYTXQ2awKdNEFEWra3P0t1_v1";
  var T_PLAYER = "usr_nmexs7bytxq2_coastal_stroll_player";
  var T_PLACES = "usr_nmexs7bytxq2_coastal_stroll_places";

  window.__gogi = { ready: false, uid: "", state: null, places: [] };

  var client = null;
  try {
    if (window.supabase && window.supabase.createClient) {
      client = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
        auth: { persistSession: true, autoRefreshToken: true }
      });
    }
  } catch (e) { client = null; }

  function finishReady() { window.__gogi.ready = true; }

  async function boot() {
    if (!client) { finishReady(); return; }
    try {
      var s = await client.auth.getSession();
      var have = s && s.data && s.data.session;
      if (!have) {
        var r = await client.auth.signInWithPassword({ email: EMAIL, password: PASSWORD });
        if (r.error) {
          // first ever run on a brand-new project state: create then sign in
          await client.auth.signUp({ email: EMAIL, password: PASSWORD });
          await client.auth.signInWithPassword({ email: EMAIL, password: PASSWORD });
        }
      }
      var u = await client.auth.getUser();
      var uid = u && u.data && u.data.user ? u.data.user.id : "";
      window.__gogi.uid = uid;
      if (uid) {
        var ps = await client.from(T_PLAYER).select("*").eq("user_id", uid).maybeSingle();
        if (ps && ps.data) window.__gogi.state = ps.data;
        var pl = await client.from(T_PLACES).select("place_id").eq("user_id", uid);
        if (pl && pl.data) window.__gogi.places = pl.data.map(function (r) { return r.place_id; });
      }
    } catch (e) { /* offline / blocked -> play without persistence */ }
    finishReady();
  }

  window.gogiSave = function (x, y, z, facing, zone) {
    if (!client || !window.__gogi.uid) return;
    window.__gogi_last = [x, y, z, facing, zone];
    var row = {
      user_id: window.__gogi.uid,
      pos_x: x, pos_y: y, pos_z: z, facing: facing, zone: String(zone),
      updated_at: new Date().toISOString()
    };
    try {
      client.from(T_PLAYER).upsert(row, { onConflict: "user_id" }).then(function () {}, function () {});
    } catch (e) {}
  };

  window.gogiDiscover = function (place_id, place_name) {
    if (!client || !window.__gogi.uid) return;
    if (window.__gogi.places.indexOf(place_id) < 0) window.__gogi.places.push(place_id);
    var row = { user_id: window.__gogi.uid, place_id: String(place_id), place_name: String(place_name) };
    try {
      client.from(T_PLACES).upsert(row, { onConflict: "user_id,place_id", ignoreDuplicates: true }).then(function () {}, function () {});
    } catch (e) {}
  };

  // flush the latest position when the tab is hidden / closed
  window.addEventListener("pagehide", function () {
    try { if (window.__gogi_last) window.gogiSave.apply(null, window.__gogi_last); } catch (e) {}
  });

  boot();
})();

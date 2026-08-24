class SaneBackendsNegaflow < Formula
  desc "SANE scanner backends with Coolscan depth-list, epson2 scan-height/infrared and OpticFilm Gray fixes"
  homepage "https://www.sane-project.org/"
  url "https://gitlab.com/-/project/429008/uploads/843c156420e211859e974f78f64c3ea3/sane-backends-1.4.0.tar.gz"
  version "1.4.0-negaflow.4"
  sha256 "f99205c903dfe2fb8990f0c531232c9a00ec9c2c66ac7cb0ce50b4af9f407a72"
  license "GPL-2.0-or-later"

  keg_only "negaflow-scanner-sane invokes this patched scanimage by its absolute path"

  depends_on "pkgconf" => :build
  depends_on "jpeg-turbo"
  depends_on "libpng"
  depends_on "libtiff"
  depends_on "libusb"
  depends_on macos: :tahoe
  depends_on "net-snmp"
  uses_from_macos "python" => :build
  uses_from_macos "libxml2"

  patch :DATA

  def install
    system "./configure",
           "--enable-local-backends",
           "--localstatedir=#{var}",
           "--sysconfdir=#{prefix}/etc",
           "--without-gphoto2",
           "--with-usb=yes",
           *std_configure_args
    system "make", "install"
    (var/"lock/sane").mkpath
  end

  test do
    assert_match prefix.to_s, shell_output("#{bin}/sane-config --prefix")
    assert_match "1.4.0", shell_output("#{bin}/scanimage --version")
  end
end

__END__
diff --git a/backend/coolscan2.c b/backend/coolscan2.c
index b87e147d..28219e8e 100644
--- a/backend/coolscan2.c
+++ b/backend/coolscan2.c
@@ -546 +546 @@ cs2_init_options (cs2_t * s)
-	  word_list = (SANE_Word *) cs2_xmalloc (2 * sizeof (SANE_Word));
+	  word_list = (SANE_Word *) cs2_xmalloc (3 * sizeof (SANE_Word));
diff --git a/backend/coolscan3.c b/backend/coolscan3.c
index e7488f8f..ff9393eb 100644
--- a/backend/coolscan3.c
+++ b/backend/coolscan3.c
@@ -506 +506 @@ cs3_init_options(cs3_t * s)
-				(SANE_Word *) cs3_xmalloc(2 *
+				(SANE_Word *) cs3_xmalloc(3 *
diff --git a/backend/epson2-ops.c b/backend/epson2-ops.c
--- a/backend/epson2-ops.c
+++ b/backend/epson2-ops.c
@@ -1423 +1423 @@ e2_init_parameters(Epson_Scanner * s)
-			((int) SANE_UNFIX(s->val[OPT_BR_Y].w) / MM_PER_INCH *
+			(SANE_UNFIX(s->val[OPT_BR_Y].w) / MM_PER_INCH *
diff --git a/backend/epson2.c b/backend/epson2.c
--- a/backend/epson2.c
+++ b/backend/epson2.c
@@ -97 +96,0 @@
-#ifdef SANE_FRAME_IR
@@ -99 +97,0 @@
-#endif
diff --git a/backend/epson2-ops.c b/backend/epson2-ops.c
--- a/backend/epson2-ops.c
+++ b/backend/epson2-ops.c
@@ -1374 +1373,0 @@
-#ifdef SANE_FRAME_IR
@@ -1376 +1375 @@
-		s->params.format = SANE_FRAME_IR;
+		s->params.format = SANE_FRAME_GRAY;
@@ -1380 +1378,0 @@
-#endif
--- a/backend/genesys/genesys.cpp
+++ b/backend/genesys/genesys.cpp
@@ -4727,7 +4727,8 @@
   s->opt[OPT_COLOR_FILTER].type = SANE_TYPE_STRING;
   s->opt[OPT_COLOR_FILTER].constraint_type = SANE_CONSTRAINT_STRING_LIST;
   /* true gray not yet supported for GL847 and GL124 scanners */
-    if (!model->is_cis || model->asic_type==AsicType::GL847 || model->asic_type==AsicType::GL124) {
+    if ((!model->is_cis && !has_flag(model->flags, ModelFlag::HOST_SIDE_GRAY)) ||
+        model->asic_type == AsicType::GL847 || model->asic_type == AsicType::GL124) {
       s->opt[OPT_COLOR_FILTER].size = max_string_size (color_filter_list);
       s->opt[OPT_COLOR_FILTER].constraint.string_list = color_filter_list;
       s->color_filter = s->opt[OPT_COLOR_FILTER].constraint.string_list[1];
--- a/backend/genesys/tables_model.cpp
+++ b/backend/genesys/tables_model.cpp
@@ -2582,9 +2582,22 @@
     model.gpio_id = GpioId::PLUSTEK_OPTICFILM_7400;
     model.motor_id = MotorId::PLUSTEK_OPTICFILM_7400;
 
+    /* Single-channel Gray acquisition reaches begin_scan but never produces
+       data on this hardware: dark and white calibration finish, begin_scan
+       returns, and wait_until_buffer_non_empty() then sees the device buffer
+       stay at zero forever.  Use the streaming RGB-to-Gray pipeline SANE
+       already has instead; the 8100 model below inherits this table row.
+
+       Device evidence is one OpticFilm 8100 (0x07b3/0x130c) on Windows.  The
+       other OpticFilm rows -- 7200 (GL842), 7200i/7300/7400-v1/7500i/
+       7600i-v1 (GL843), 8200i/7600i-v2 (GL845) -- are separate table rows
+       and are deliberately NOT flagged: host-side Gray acquires three
+       channels, so turning it on for a device whose native Gray works would
+       be a regression.  Flip a row only with a scan from that device.  */
     model.flags = ModelFlag::CUSTOM_GAMMA |
                   ModelFlag::DARK_CALIBRATION |
-                  ModelFlag::SHADING_REPARK;
+                  ModelFlag::SHADING_REPARK |
+                  ModelFlag::HOST_SIDE_GRAY;
 
     model.search_lines = 200;
     s_usb_devices->emplace_back(0x07b3, 0x0c3a, 0x0605, model);
--- a/backend/genesys/gl846.cpp
+++ b/backend/genesys/gl846.cpp
@@ -661,6 +661,20 @@
     dev->total_bytes_read = 0;
     dev->total_bytes_to_read = (size_t)session.output_line_bytes_requested * (size_t)session.params.lines;
 
+    /* `output_line_bytes_requested` counts the three channels the sensor
+       really acquires, but host-side Gray merges them to one before the
+       frontend sees a byte, and sane_get_parameters() already announces the
+       one-channel size.  Without this the read loop keeps pulling until it
+       has three times the image and the frontend reports
+       `read more data than announced by backend (3030240/1010080)`.
+
+       Keyed on the session, not on any model: gl841.cpp -- the only command
+       set upstream ever ran host-side Gray on -- divides here for exactly
+       the same reason.  GL845/GL846 never got the line.  */
+    if (session.use_host_side_gray) {
+        dev->total_bytes_to_read /= 3;
+    }
+
     DBG(DBG_info, "%s: total bytes to send = %zu\n", __func__, dev->total_bytes_to_read);
 }
 

class SaneBackendsNegaflow < Formula
  desc "SANE backends with Coolscan, epson2 (incl. V500 Photo) and OpticFilm fixes and upstream OpticFilm 8200i SE support"
  homepage "https://www.sane-project.org/"
  url "https://gitlab.com/-/project/429008/uploads/843c156420e211859e974f78f64c3ea3/sane-backends-1.4.0.tar.gz"
  version "1.4.0-negaflow.6"
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
 
diff --git a/backend/Makefile.am b/backend/Makefile.am
index 4bf4e6f..58252b3 100644
--- a/backend/Makefile.am
+++ b/backend/Makefile.am
@@ -763,6 +763,7 @@ libgenesys_la_SOURCES = genesys/genesys.cpp genesys/genesys.h \
     genesys/fwd.h \
     genesys/gl646.cpp genesys/gl646.h genesys/gl646_registers.h \
     genesys/gl124.cpp genesys/gl124.h genesys/gl124_registers.h \
+    genesys/gl128.cpp genesys/gl128.h genesys/gl128_registers.h \
     genesys/gl841.cpp genesys/gl841.h genesys/gl841_registers.h \
     genesys/gl842.cpp genesys/gl842.h genesys/gl842_registers.h \
     genesys/gl843.cpp genesys/gl843.h genesys/gl843_registers.h \
diff --git a/backend/Makefile.in b/backend/Makefile.in
index f27c65d..f10e7eb 100644
--- a/backend/Makefile.in
+++ b/backend/Makefile.in
@@ -266,7 +266,8 @@ am_libgenesys_la_OBJECTS = genesys/libgenesys_la-genesys.lo \
 	genesys/libgenesys_la-command_set_common.lo \
 	genesys/libgenesys_la-device.lo genesys/libgenesys_la-enums.lo \
 	genesys/libgenesys_la-error.lo genesys/libgenesys_la-gl646.lo \
-	genesys/libgenesys_la-gl124.lo genesys/libgenesys_la-gl841.lo \
+	genesys/libgenesys_la-gl124.lo genesys/libgenesys_la-gl128.lo \
+	genesys/libgenesys_la-gl841.lo \
 	genesys/libgenesys_la-gl842.lo genesys/libgenesys_la-gl843.lo \
 	genesys/libgenesys_la-gl846.lo genesys/libgenesys_la-gl847.lo \
 	genesys/libgenesys_la-image_buffer.lo \
@@ -1963,6 +1964,7 @@ am__depfiles_remade = ./$(DEPDIR)/libabaton_la-abaton.Plo \
 	genesys/$(DEPDIR)/libgenesys_la-error.Plo \
 	genesys/$(DEPDIR)/libgenesys_la-genesys.Plo \
 	genesys/$(DEPDIR)/libgenesys_la-gl124.Plo \
+	genesys/$(DEPDIR)/libgenesys_la-gl128.Plo \
 	genesys/$(DEPDIR)/libgenesys_la-gl646.Plo \
 	genesys/$(DEPDIR)/libgenesys_la-gl841.Plo \
 	genesys/$(DEPDIR)/libgenesys_la-gl842.Plo \
@@ -3154,6 +3156,7 @@ libgenesys_la_SOURCES = genesys/genesys.cpp genesys/genesys.h \
     genesys/fwd.h \
     genesys/gl646.cpp genesys/gl646.h genesys/gl646_registers.h \
     genesys/gl124.cpp genesys/gl124.h genesys/gl124_registers.h \
+    genesys/gl128.cpp genesys/gl128.h genesys/gl128_registers.h \
     genesys/gl841.cpp genesys/gl841.h genesys/gl841_registers.h \
     genesys/gl842.cpp genesys/gl842.h genesys/gl842_registers.h \
     genesys/gl843.cpp genesys/gl843.h genesys/gl843_registers.h \
@@ -4543,6 +4546,8 @@ genesys/libgenesys_la-gl646.lo: genesys/$(am__dirstamp) \
 	genesys/$(DEPDIR)/$(am__dirstamp)
 genesys/libgenesys_la-gl124.lo: genesys/$(am__dirstamp) \
 	genesys/$(DEPDIR)/$(am__dirstamp)
+genesys/libgenesys_la-gl128.lo: genesys/$(am__dirstamp) \
+	genesys/$(DEPDIR)/$(am__dirstamp)
 genesys/libgenesys_la-gl841.lo: genesys/$(am__dirstamp) \
 	genesys/$(DEPDIR)/$(am__dirstamp)
 genesys/libgenesys_la-gl842.lo: genesys/$(am__dirstamp) \
@@ -5359,6 +5364,7 @@ distclean-compile:
 @AMDEP_TRUE@@am__include@ @am__quote@genesys/$(DEPDIR)/libgenesys_la-error.Plo@am__quote@ # am--include-marker
 @AMDEP_TRUE@@am__include@ @am__quote@genesys/$(DEPDIR)/libgenesys_la-genesys.Plo@am__quote@ # am--include-marker
 @AMDEP_TRUE@@am__include@ @am__quote@genesys/$(DEPDIR)/libgenesys_la-gl124.Plo@am__quote@ # am--include-marker
+@AMDEP_TRUE@@am__include@ @am__quote@genesys/$(DEPDIR)/libgenesys_la-gl128.Plo@am__quote@ # am--include-marker
 @AMDEP_TRUE@@am__include@ @am__quote@genesys/$(DEPDIR)/libgenesys_la-gl646.Plo@am__quote@ # am--include-marker
 @AMDEP_TRUE@@am__include@ @am__quote@genesys/$(DEPDIR)/libgenesys_la-gl841.Plo@am__quote@ # am--include-marker
 @AMDEP_TRUE@@am__include@ @am__quote@genesys/$(DEPDIR)/libgenesys_la-gl842.Plo@am__quote@ # am--include-marker
@@ -7229,6 +7235,13 @@ genesys/libgenesys_la-gl124.lo: genesys/gl124.cpp
 @AMDEP_TRUE@@am__fastdepCXX_FALSE@	DEPDIR=$(DEPDIR) $(CXXDEPMODE) $(depcomp) @AMDEPBACKSLASH@
 @am__fastdepCXX_FALSE@	$(AM_V_CXX@am__nodep@)$(LIBTOOL) $(AM_V_lt) --tag=CXX $(AM_LIBTOOLFLAGS) $(LIBTOOLFLAGS) --mode=compile $(CXX) $(DEFS) $(DEFAULT_INCLUDES) $(INCLUDES) $(libgenesys_la_CPPFLAGS) $(CPPFLAGS) $(AM_CXXFLAGS) $(CXXFLAGS) -c -o genesys/libgenesys_la-gl124.lo `test -f 'genesys/gl124.cpp' || echo '$(srcdir)/'`genesys/gl124.cpp
 
+genesys/libgenesys_la-gl128.lo: genesys/gl128.cpp
+@am__fastdepCXX_TRUE@	$(AM_V_CXX)$(LIBTOOL) $(AM_V_lt) --tag=CXX $(AM_LIBTOOLFLAGS) $(LIBTOOLFLAGS) --mode=compile $(CXX) $(DEFS) $(DEFAULT_INCLUDES) $(INCLUDES) $(libgenesys_la_CPPFLAGS) $(CPPFLAGS) $(AM_CXXFLAGS) $(CXXFLAGS) -MT genesys/libgenesys_la-gl128.lo -MD -MP -MF genesys/$(DEPDIR)/libgenesys_la-gl128.Tpo -c -o genesys/libgenesys_la-gl128.lo `test -f 'genesys/gl128.cpp' || echo '$(srcdir)/'`genesys/gl128.cpp
+@am__fastdepCXX_TRUE@	$(AM_V_at)$(am__mv) genesys/$(DEPDIR)/libgenesys_la-gl128.Tpo genesys/$(DEPDIR)/libgenesys_la-gl128.Plo
+@AMDEP_TRUE@@am__fastdepCXX_FALSE@	$(AM_V_CXX)source='genesys/gl128.cpp' object='genesys/libgenesys_la-gl128.lo' libtool=yes @AMDEPBACKSLASH@
+@AMDEP_TRUE@@am__fastdepCXX_FALSE@	DEPDIR=$(DEPDIR) $(CXXDEPMODE) $(depcomp) @AMDEPBACKSLASH@
+@am__fastdepCXX_FALSE@	$(AM_V_CXX@am__nodep@)$(LIBTOOL) $(AM_V_lt) --tag=CXX $(AM_LIBTOOLFLAGS) $(LIBTOOLFLAGS) --mode=compile $(CXX) $(DEFS) $(DEFAULT_INCLUDES) $(INCLUDES) $(libgenesys_la_CPPFLAGS) $(CPPFLAGS) $(AM_CXXFLAGS) $(CXXFLAGS) -c -o genesys/libgenesys_la-gl128.lo `test -f 'genesys/gl128.cpp' || echo '$(srcdir)/'`genesys/gl128.cpp
+
 genesys/libgenesys_la-gl841.lo: genesys/gl841.cpp
 @am__fastdepCXX_TRUE@	$(AM_V_CXX)$(LIBTOOL) $(AM_V_lt) --tag=CXX $(AM_LIBTOOLFLAGS) $(LIBTOOLFLAGS) --mode=compile $(CXX) $(DEFS) $(DEFAULT_INCLUDES) $(INCLUDES) $(libgenesys_la_CPPFLAGS) $(CPPFLAGS) $(AM_CXXFLAGS) $(CXXFLAGS) -MT genesys/libgenesys_la-gl841.lo -MD -MP -MF genesys/$(DEPDIR)/libgenesys_la-gl841.Tpo -c -o genesys/libgenesys_la-gl841.lo `test -f 'genesys/gl841.cpp' || echo '$(srcdir)/'`genesys/gl841.cpp
 @am__fastdepCXX_TRUE@	$(AM_V_at)$(am__mv) genesys/$(DEPDIR)/libgenesys_la-gl841.Tpo genesys/$(DEPDIR)/libgenesys_la-gl841.Plo
@@ -7818,6 +7831,7 @@ distclean: distclean-am
 	-rm -f genesys/$(DEPDIR)/libgenesys_la-error.Plo
 	-rm -f genesys/$(DEPDIR)/libgenesys_la-genesys.Plo
 	-rm -f genesys/$(DEPDIR)/libgenesys_la-gl124.Plo
+	-rm -f genesys/$(DEPDIR)/libgenesys_la-gl128.Plo
 	-rm -f genesys/$(DEPDIR)/libgenesys_la-gl646.Plo
 	-rm -f genesys/$(DEPDIR)/libgenesys_la-gl841.Plo
 	-rm -f genesys/$(DEPDIR)/libgenesys_la-gl842.Plo
@@ -8146,6 +8160,7 @@ maintainer-clean: maintainer-clean-am
 	-rm -f genesys/$(DEPDIR)/libgenesys_la-error.Plo
 	-rm -f genesys/$(DEPDIR)/libgenesys_la-genesys.Plo
 	-rm -f genesys/$(DEPDIR)/libgenesys_la-gl124.Plo
+	-rm -f genesys/$(DEPDIR)/libgenesys_la-gl128.Plo
 	-rm -f genesys/$(DEPDIR)/libgenesys_la-gl646.Plo
 	-rm -f genesys/$(DEPDIR)/libgenesys_la-gl841.Plo
 	-rm -f genesys/$(DEPDIR)/libgenesys_la-gl842.Plo
diff --git a/backend/genesys.conf.in b/backend/genesys.conf.in
index 6e6a8d7..39d32c2 100644
--- a/backend/genesys.conf.in
+++ b/backend/genesys.conf.in
@@ -155,6 +155,9 @@ usb 0x07b3 0x130c
 # Plustek OpticFilm 8200i
 usb 0x07b3 0x130d
 
+# Plustek OpticFilm 8200i SE (GL128)
+usb 0x07b3 0x1825
+
 # Primax Electronics, Ltd Xerox 2400 Onetouch
 usb 0x0461 0x038b
 
diff --git a/backend/genesys/device.cpp b/backend/genesys/device.cpp
index 5411d7b..cec18b4 100644
--- a/backend/genesys/device.cpp
+++ b/backend/genesys/device.cpp
@@ -25,6 +25,8 @@
 #include "low.h"
 #include "utilities.h"
 
+#include <iterator>
+
 namespace genesys {
 
 std::vector<unsigned> MethodResolutions::get_resolutions() const
@@ -231,6 +233,8 @@ std::ostream& operator<<(std::ostream& out, const Genesys_Device& dev)
         << "    read_active: " << dev.read_active << '\n'
         << "    parking: " << dev.parking << '\n'
         << "    document: " << dev.document << '\n'
+        << "    lamp_warmup_pending: " << dev.lamp_warmup_pending << '\n'
+        << "    lamp_boot_sequence_pending: " << dev.lamp_boot_sequence_pending << '\n'
         << "    total_bytes_read: " << dev.total_bytes_read << '\n'
         << "    total_bytes_to_read: " << dev.total_bytes_to_read << '\n'
         << "    session: " << format_indent_braced_list(4, dev.session) << '\n'
diff --git a/backend/genesys/device.h b/backend/genesys/device.h
index 842856b..5f6b6c8 100644
--- a/backend/genesys/device.h
+++ b/backend/genesys/device.h
@@ -294,6 +294,12 @@ struct Genesys_Device
     // for sheetfed scanner's, is TRUE when there is a document in the scanner
     bool document = false;
 
+    // set by asic_boot() of chips whose lamp needs it (GL128): the lamp must warm up before the
+    // next calibration (cold start), and the lamp control sequence of the first calibration after
+    // boot is still to be sent
+    bool lamp_warmup_pending = false;
+    bool lamp_boot_sequence_pending = false;
+
     // total bytes read sent to frontend
     size_t total_bytes_read = 0;
     // total bytes read to be sent to frontend
diff --git a/backend/genesys/enums.cpp b/backend/genesys/enums.cpp
index 460e73f..4012e0b 100644
--- a/backend/genesys/enums.cpp
+++ b/backend/genesys/enums.cpp
@@ -124,6 +124,7 @@ std::ostream& operator<<(std::ostream& out, ModelId id)
         case ModelId::PLUSTEK_OPTICFILM_7400: out << "PLUSTEK_OPTICFILM_7400"; break;
         case ModelId::PLUSTEK_OPTICFILM_7500I: out << "PLUSTEK_OPTICFILM_7500I"; break;
         case ModelId::PLUSTEK_OPTICFILM_8200I: out << "PLUSTEK_OPTICFILM_8200I"; break;
+        case ModelId::PLUSTEK_OPTICFILM_8200I_SE: out << "PLUSTEK_OPTICFILM_8200I_SE"; break;
         case ModelId::PLUSTEK_OPTICPRO_3600: out << "PLUSTEK_OPTICPRO_3600"; break;
         case ModelId::PLUSTEK_OPTICPRO_ST12: out << "PLUSTEK_OPTICPRO_ST12"; break;
         case ModelId::PLUSTEK_OPTICPRO_ST24: out << "PLUSTEK_OPTICPRO_ST24"; break;
@@ -171,9 +172,12 @@ std::ostream& operator<<(std::ostream& out, SensorId id)
         case SensorId::CCD_PLUSTEK_OPTICFILM_7200: out << "CCD_PLUSTEK_OPTICFILM_7200"; break;
         case SensorId::CCD_PLUSTEK_OPTICFILM_7200I: out << "CCD_PLUSTEK_OPTICFILM_7200I"; break;
         case SensorId::CCD_PLUSTEK_OPTICFILM_7300: out << "CCD_PLUSTEK_OPTICFILM_7300"; break;
-        case SensorId::CCD_PLUSTEK_OPTICFILM_7400: out << "CCD_PLUSTEK_OPTICFILM_7400"; break;
+        case SensorId::CCD_PLUSTEK_OPTICFILM_7400_V1: out << "CCD_PLUSTEK_OPTICFILM_7400_V1"; break;
+        case SensorId::CCD_PLUSTEK_OPTICFILM_7400_V2: out << "CCD_PLUSTEK_OPTICFILM_7400_V2"; break;
         case SensorId::CCD_PLUSTEK_OPTICFILM_7500I: out << "CCD_PLUSTEK_OPTICFILM_7500I"; break;
+        case SensorId::CCD_PLUSTEK_OPTICFILM_7600I_V1: out << "CCD_PLUSTEK_OPTICFILM_7600I_V1"; break;
         case SensorId::CCD_PLUSTEK_OPTICFILM_8200I: out << "CCD_PLUSTEK_OPTICFILM_8200I"; break;
+        case SensorId::CCD_PLUSTEK_OPTICFILM_8200I_SE: out << "CCD_PLUSTEK_OPTICFILM_8200I_SE"; break;
         case SensorId::CCD_PLUSTEK_OPTICPRO_3600: out << "CCD_PLUSTEK_OPTICPRO_3600"; break;
         case SensorId::CCD_ROADWARRIOR: out << "CCD_ROADWARRIOR"; break;
         case SensorId::CCD_ST12: out << "CCD_ST12"; break;
@@ -224,6 +228,7 @@ std::ostream& operator<<(std::ostream& out, AdcId id)
         case AdcId::PLUSTEK_OPTICFILM_7400: out << "PLUSTEK_OPTICFILM_7400"; break;
         case AdcId::PLUSTEK_OPTICFILM_7500I: out << "PLUSTEK_OPTICFILM_7500I"; break;
         case AdcId::PLUSTEK_OPTICFILM_8200I: out << "PLUSTEK_OPTICFILM_8200I"; break;
+        case AdcId::PLUSTEK_OPTICFILM_8200I_SE: out << "PLUSTEK_OPTICFILM_8200I_SE"; break;
         case AdcId::PLUSTEK_OPTICPRO_3600: out << "PLUSTEK_OPTICPRO_3600"; break;
         case AdcId::WOLFSON_5345: out << "WOLFSON_5345"; break;
         case AdcId::WOLFSON_DSM600: out << "WOLFSON_DSM600"; break;
@@ -273,6 +278,7 @@ std::ostream& operator<<(std::ostream& out, GpioId id)
         case GpioId::PLUSTEK_OPTICFILM_7400: out << "PLUSTEK_OPTICFILM_7400"; break;
         case GpioId::PLUSTEK_OPTICFILM_7500I: out << "PLUSTEK_OPTICFILM_7500I"; break;
         case GpioId::PLUSTEK_OPTICFILM_8200I: out << "PLUSTEK_OPTICFILM_8200I"; break;
+        case GpioId::PLUSTEK_OPTICFILM_8200I_SE: out << "PLUSTEK_OPTICFILM_8200I_SE"; break;
         case GpioId::PLUSTEK_OPTICPRO_3600: out << "PLUSTEK_OPTICPRO_3600"; break;
         case GpioId::ST12: out << "ST12"; break;
         case GpioId::ST24: out << "ST24"; break;
@@ -318,6 +324,7 @@ std::ostream& operator<<(std::ostream& out, MotorId id)
         case MotorId::PLUSTEK_OPTICFILM_7400: out << "PLUSTEK_OPTICFILM_7400"; break;
         case MotorId::PLUSTEK_OPTICFILM_7500I: out << "PLUSTEK_OPTICFILM_7500I"; break;
         case MotorId::PLUSTEK_OPTICFILM_8200I: out << "PLUSTEK_OPTICFILM_8200I"; break;
+        case MotorId::PLUSTEK_OPTICFILM_8200I_SE: out << "PLUSTEK_OPTICFILM_8200I_SE"; break;
         case MotorId::PLUSTEK_OPTICPRO_3600: out << "PLUSTEK_OPTICPRO_3600"; break;
         case MotorId::ROADWARRIOR: out << "ROADWARRIOR"; break;
         case MotorId::ST24: out << "ST24"; break;
diff --git a/backend/genesys/enums.h b/backend/genesys/enums.h
index 88fc9c3..b8db6fa 100644
--- a/backend/genesys/enums.h
+++ b/backend/genesys/enums.h
@@ -185,6 +185,7 @@ enum class ModelId : unsigned
     PLUSTEK_OPTICFILM_7400,
     PLUSTEK_OPTICFILM_7500I,
     PLUSTEK_OPTICFILM_8200I,
+    PLUSTEK_OPTICFILM_8200I_SE,
     PLUSTEK_OPTICPRO_3600,
     PLUSTEK_OPTICPRO_ST12,
     PLUSTEK_OPTICPRO_ST24,
@@ -242,9 +243,12 @@ enum class SensorId : unsigned
     CCD_PLUSTEK_OPTICFILM_7200,
     CCD_PLUSTEK_OPTICFILM_7200I,
     CCD_PLUSTEK_OPTICFILM_7300,
-    CCD_PLUSTEK_OPTICFILM_7400,
+    CCD_PLUSTEK_OPTICFILM_7400_V1,
+    CCD_PLUSTEK_OPTICFILM_7400_V2,
     CCD_PLUSTEK_OPTICFILM_7500I,
+    CCD_PLUSTEK_OPTICFILM_7600I_V1,
     CCD_PLUSTEK_OPTICFILM_8200I,
+    CCD_PLUSTEK_OPTICFILM_8200I_SE,
     CCD_PLUSTEK_OPTICPRO_3600,
     CCD_ROADWARRIOR,
     CCD_ST12,         // SONY ILX548: 5340 Pixel  ???
@@ -306,6 +310,7 @@ enum class AdcId : unsigned
     PLUSTEK_OPTICFILM_7400,
     PLUSTEK_OPTICFILM_7500I,
     PLUSTEK_OPTICFILM_8200I,
+    PLUSTEK_OPTICFILM_8200I_SE,
     PLUSTEK_OPTICPRO_3600,
     WOLFSON_5345,
     WOLFSON_DSM600,
@@ -366,6 +371,7 @@ enum class GpioId : unsigned
     PLUSTEK_OPTICFILM_7400,
     PLUSTEK_OPTICFILM_7500I,
     PLUSTEK_OPTICFILM_8200I,
+    PLUSTEK_OPTICFILM_8200I_SE,
     PLUSTEK_OPTICPRO_3600,
     ST12,
     ST24,
@@ -409,6 +415,7 @@ enum class MotorId : unsigned
     PLUSTEK_OPTICFILM_7400,
     PLUSTEK_OPTICFILM_7500I,
     PLUSTEK_OPTICFILM_8200I,
+    PLUSTEK_OPTICFILM_8200I_SE,
     PLUSTEK_OPTICPRO_3600,
     ROADWARRIOR,
     ST24,
@@ -457,6 +464,7 @@ enum class AsicType : unsigned
     GL846,
     GL847,
     GL124,
+    GL128,
 };
 
 
diff --git a/backend/genesys/genesys.cpp b/backend/genesys/genesys.cpp
index 2c81577..99b7867 100644
--- a/backend/genesys/genesys.cpp
+++ b/backend/genesys/genesys.cpp
@@ -39,6 +39,7 @@
 
 #include "genesys.h"
 #include "gl124_registers.h"
+#include "gl128_registers.h"
 #include "gl841_registers.h"
 #include "gl842_registers.h"
 #include "gl843_registers.h"
@@ -481,6 +482,10 @@ void scanner_clear_scan_and_feed_counts(Genesys_Device& dev)
                                           gl124::REG_0x0D_CLRLNCNT | gl124::REG_0x0D_CLRMCNT);
             break;
         }
+        case AsicType::GL128: {
+            dev.interface->write_register(gl128::REG_CLRCNT, gl128::CLRCNT_ALL);
+            break;
+        }
         default:
             throw SaneException("Unsupported asic type");
     }
@@ -639,6 +644,11 @@ bool scanner_is_motor_stopped(Genesys_Device& dev)
             return (!(reg & gl124::REG_0x100_DATAENB) && !(reg & gl124::REG_0x100_MOTMFLG) &&
                     !status.is_motor_enabled);
         }
+        case AsicType::GL128: {
+            // No DATAENB/MOTMFLG register as on GL124; status only.
+            auto status = scanner_read_status(dev);
+            return !status.is_motor_enabled && status.is_feeding_finished;
+        }
         default:
             throw SaneException("Unsupported asic type");
     }
@@ -674,6 +684,7 @@ void scanner_stop_action(Genesys_Device& dev)
         case AsicType::GL846:
         case AsicType::GL847:
         case AsicType::GL124:
+        case AsicType::GL128:
             break;
         default:
             throw SaneException("Unsupported asic type");
@@ -714,6 +725,7 @@ void scanner_stop_action_no_move(Genesys_Device& dev, genesys::Genesys_Register_
         case AsicType::GL846:
         case AsicType::GL847:
         case AsicType::GL124:
+        case AsicType::GL128:
             break;
         default:
             throw SaneException("Unsupported asic type");
@@ -733,6 +745,12 @@ void scanner_move(Genesys_Device& dev, ScanMethod scan_method, unsigned steps, D
     DBG_HELPER_ARGS(dbg, "steps=%d direction=%d", steps, static_cast<unsigned>(direction));
 
     auto local_reg = dev.reg;
+    // GL128: a zero-step feed does nothing. Starting the motor with AGOHOME
+    // armed at home (scanner_move_to_ta() on this transparency-only scanner)
+    // hangs with status 0xcd.
+    if (dev.model->asic_type == AsicType::GL128 && steps == 0) {
+        return;
+    }
 
     unsigned resolution = dev.model->get_resolution_settings(scan_method).get_min_resolution_y();
 
@@ -3385,8 +3403,10 @@ static void genesys_send_shading_coefficient(Genesys_Device* dev, const Genesys_
         case SensorId::CCD_PLUSTEK_OPTICFILM_7200:
     case SensorId::CCD_PLUSTEK_OPTICFILM_7200I:
     case SensorId::CCD_PLUSTEK_OPTICFILM_7300:
-        case SensorId::CCD_PLUSTEK_OPTICFILM_7400:
+    case SensorId::CCD_PLUSTEK_OPTICFILM_7400_V1:
+    case SensorId::CCD_PLUSTEK_OPTICFILM_7400_V2:
     case SensorId::CCD_PLUSTEK_OPTICFILM_7500I:
+    case SensorId::CCD_PLUSTEK_OPTICFILM_7600I_V1:
         case SensorId::CCD_PLUSTEK_OPTICFILM_8200I:
       target_code = 0xe000;
       o = 0;
@@ -4180,7 +4200,7 @@ static std::size_t max_string_size(const std::vector<const char*>& strings)
         if (!s) {
             continue;
         }
-        max_size = std::max(max_size, std::strlen(s));
+        max_size = std::max(max_size, std::strlen(s) + 1);
     }
     return max_size;
 }
diff --git a/backend/genesys/gl128.cpp b/backend/genesys/gl128.cpp
new file mode 100644
index 0000000..750c8f2
--- /dev/null
+++ b/backend/genesys/gl128.cpp
@@ -0,0 +1,2169 @@
+/* sane - Scanner Access Now Easy.
+
+   Copyright (C) 2026 vermiculous <vermiculous@disroot.org>
+   Portions derived from pyopticfilm (https://github.com/jboneng/pyopticfilm),
+   Copyright (C) jboneng, used with permission.
+
+   This file is part of the SANE package.
+
+   This program is free software; you can redistribute it and/or
+   modify it under the terms of the GNU General Public License as
+   published by the Free Software Foundation; either version 2 of the
+   License, or (at your option) any later version.
+
+   This program is distributed in the hope that it will be useful, but
+   WITHOUT ANY WARRANTY; without even the implied warranty of
+   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
+   General Public License for more details.
+
+   You should have received a copy of the GNU General Public License
+   along with this program.  If not, see <https://www.gnu.org/licenses/>.
+*/
+
+/*
+ * GL128 command set (Plustek OpticFilm 8200i SE, USB 07b3:1825).
+ *
+ * The GL128 is a GL124-family ASIC. Register values, sequences and tables in
+ * this file come from USB captures of the vendor driver (SilverFast) on this
+ * scanner, largely as decoded by the pyopticfilm project; the source of each
+ * value is noted next to it.
+ */
+
+#define DEBUG_DECLARE_ONLY
+
+#include "gl128.h"
+#include "gl128_registers.h"
+#include <algorithm>
+#include <array>
+#include <chrono>
+#include <cmath>
+#include <functional>
+#include <iterator>
+#include <thread>
+#include <utility>
+#include <vector>
+
+namespace genesys {
+namespace gl128 {
+
+namespace {
+
+// --- Device tables -------------------------------------------------------------
+// Values that belong to a scanner model rather than to the GL128 chip, keyed by
+// sensor, as gl646.cpp keeps its motor and sensor master tables. Per-resolution
+// sensor values are in tables_sensor.cpp and the motor slopes in
+// tables_motor.cpp; these are the ones the shared structures have no field for.
+
+// 0x2b (dummy) and 0xa5/0xab (pixel clocks) for one pass.
+struct Gl128PassClocks {
+    unsigned dummy;
+    unsigned clk_a;
+    unsigned clk_b;
+};
+
+// Line timing for one scan: LPERIOD (shared by the dark, white and image
+// passes, as in every SilverFast capture) and the per-pass clocks.
+struct Gl128Timing {
+    unsigned lperiod;
+    Gl128PassClocks image;
+    Gl128PassClocks dark;
+    Gl128PassClocks white;
+};
+
+// Line timing for scan windows at most `max_width` native pixels wide.
+struct Gl128WidthProgram {
+    unsigned max_width;
+    Gl128Timing timing;
+};
+
+// Dark-strip clocks where they differ from the image pass.
+struct Gl128DarkClocks {
+    unsigned asic_dpi;
+    Gl128PassClocks clocks;
+};
+
+// Front-end offsets and gains (R, G, B).
+struct Gl128FrontendCodes {
+    std::array<int, 3> offsets;
+    std::array<int, 3> gains;
+};
+
+struct Gl128DeviceTables {
+    SensorId sensor_id;
+
+    // Stationary AFE strips (probes, lamp warm-up): window in native pixels,
+    // DPISET, clocks, line period and exposure.
+    unsigned afe_strpixel;
+    unsigned afe_endpixel;
+    unsigned afe_wide_endpixel;
+    unsigned afe_dpiset;
+    Gl128PassClocks afe_clocks;
+    unsigned afe_lperiod;
+
+    // Exposure (0x7d-0x7f) of every pass, and of the calibration exposure
+    // tables (entries 0 and 1).
+    unsigned exposure;
+
+    // Per-channel exposure tables of the image pass: 256 entries of
+    // exposure / (full_resolution / asic_dpi), entry 0 that + first_extra,
+    // except where first_override gives entry 0 for a resolution.
+    unsigned channel_first_extra;
+    unsigned channel_first_override_dpi;
+    unsigned channel_first_override;
+
+    // Front-end codes, in the order the calibration uses them.
+    std::array<int, 3> shading_offsets;         // dark, white and lamp strips
+    std::array<int, 3> lamp_gains;              // lamp warm-up, relight, white strip
+    std::vector<Gl128FrontendCodes> probes;     // AFE probes, lamp on
+    unsigned wide_probe_index;                  // the probe read over the full width
+    std::array<int, 3> after_probe_gains;       // with shading_offsets
+    std::array<int, 3> dark_gains;              // with shading_offsets
+    std::array<int, 3> image_offset_delta;      // image offsets = shading + this
+
+    // Line timing overrides.
+    std::vector<Gl128DarkClocks> dark_clocks;
+    unsigned width_program_dpi;
+    std::vector<Gl128WidthProgram> width_programs;
+
+    // Motor steps per inch of carriage travel.
+    unsigned steps_per_inch;
+
+    // Constant set-up registers of the two positioning feeds (motor, sensor
+    // and window settings the feeds do not compute). The feeds write them in
+    // the capture's order.
+    GenesysRegisterSettingSet feed1_regs;
+    GenesysRegisterSettingSet feed2_regs;
+
+    // Positioning, in motor steps: first feed, second feed to the top of the
+    // scan window, the window's end, and the furthest line the image pass may
+    // end on.
+    unsigned feed1_steps;
+    unsigned feed2_steps;
+    unsigned window_end_steps;
+    unsigned max_image_end_steps;
+
+    // Height of the scan window from feed2_steps to window_end_steps; the
+    // second feed places the crop top as a fraction of it. The height offered
+    // to frontends (y_size_ta) is smaller: the image may only run to
+    // max_image_end_steps.
+    float window_height_mm;
+
+    // Inactive native pixels at the end of the sensor, before the frame.
+    unsigned optical_end_inactive;
+};
+
+// Plustek OpticFilm 8200i SE. From SilverFast's USB captures (1800 dpi for the
+// calibration sequence and front-end codes, 600 and 7200 dpi for the feeds,
+// four 7200 dpi captures for the width programs) and pyopticfilm.
+const Gl128DeviceTables GL128_DEVICE_TABLES[] = {
+    {
+        SensorId::CCD_PLUSTEK_OPTICFILM_8200I_SE,
+        // AFE strips: STRPIXEL 64, ENDPIXEL 576 (512 px), the wide one
+        // 62268 bytes (10378 px); DPISET 1200, dummy 0x04, clocks 0x01/0x30.
+        0x40, 0x240, 0x40 + 62268 / 6, 1200, { 0x04, 0x01, 0x30 }, 14000,
+        14000,
+        // Channel exposure (pyopticfilm exposure_table()); at 600 dpi
+        // SilverFast's table has entry 0 = 3516.
+        16, 600, 3516,
+        { 39, 32, 39 },
+        { 56, 69, 61 },
+        {
+            { { 0, 0, 0 }, { 128, 128, 128 } },
+            { { 0, 0, 0 }, { 255, 255, 255 } },
+            { { 0, 0, 0 }, { 310, 278, 293 } },
+            { { 39, 32, 39 }, { 128, 128, 128 } },
+            { { 39, 32, 39 }, { 255, 255, 255 } },
+        },
+        2,
+        { 19, 26, 24 },
+        { 50, 62, 55 },
+        // SilverFast writes 41/35/42 after its white strip.
+        { 2, 3, 3 },
+        // Dark strip clocks at 1200 and 1800 dpi (pyopticfilm SHADING_DARK_*;
+        // dummy 0x04 at 1800 from SilverFast's 1800 dpi capture).
+        { { 1200, { 0x04, 0x01, 0x30 } }, { 1800, { 0x04, 0x01, 0x30 } } },
+        // 7200 dpi: SilverFast sets the line timing from the window width.
+        // Four captures (window widths 1416, 2832, 5664 and 10200 native
+        // pixels) give LPERIOD = 10851 + width / 2 exactly; the dummy and
+        // clock bytes follow no formula. Wider windows use the sensor entry.
+        7200,
+        {
+            //  width   LPERIOD  image            dark               white
+            {  1416, { 11559, { 0x03, 1, 1 }, { 0x04, 1, 0x30 }, { 0x02, 2, 2 } } },
+            {  2832, { 12267, { 0x05, 1, 1 }, { 0x07, 1, 0x30 }, { 0x03, 2, 2 } } },
+            {  5664, { 13683, { 0x09, 1, 1 }, { 0x0d, 1, 0x30 }, { 0x09, 1, 1 } } },
+            { 10200, { 15951, { 0x17, 1, 1 }, { 0x17, 1, 0x30 }, { 0x0f, 1, 1 } } },
+        },
+        14400,
+        // Feed set-up blocks, the same in the 600 and 7200 dpi captures
+        // (pyopticfilm _FEED_SETUP_REGS).
+        {
+            { 0x3b, 0x01 }, { 0x04, 0x42 }, { 0x05, 0x48 },
+            { 0xa6, 0x00 }, { 0xa7, 0x00 }, { 0xa8, 0x00 }, { 0xa9, 0x00 },
+            { 0x80, 0x00 }, { 0x81, 0x40 }, { 0x1d, 0x80 }, { 0x1c, 0x20 },
+            { 0xa4, 0x00 }, { 0xaa, 0x00 }, { 0xae, 0x00 }, { 0xaf, 0x7f },
+        },
+        {
+            { 0x1c, 0x20 },
+            { 0x8a, 0x00 }, { 0x8b, 0x00 }, { 0x8c, 0x00 }, { 0x8d, 0x00 }, { 0x8e, 0x00 },
+            { 0x8f, 0x00 }, { 0x90, 0x00 }, { 0x91, 0x00 }, { 0x92, 0x00 },
+            { 0xae, 0x00 }, { 0xaf, 0xff },
+        },
+        // Feeds (capture: 0x3d-0x3f = 00 6e 84 and 00 33 48); window end
+        // (pyopticfilm scan_window_end_steps); SilverFast's full-frame passes
+        // end at feed2 13560 plus 13752 steps (600 dpi, LINCNT 2292).
+        28292, 13128, 27636, 13560 + 13752,
+        // pyopticfilm gl128_common y_size_ta_mm (27636 - 13128 = 14508 steps).
+        25.59f,
+        // pyopticfilm optical_end_inactive_native.
+        96,
+    },
+};
+
+const Gl128DeviceTables& gl128_device_tables(const Genesys_Device* dev)
+{
+    for (const auto& t : GL128_DEVICE_TABLES) {
+        if (t.sensor_id == dev->model->sensor_id) {
+            return t;
+        }
+    }
+    throw SaneException("GL128: no device tables for this sensor");
+}
+
+// Registers set per acquisition pass rather than from the sensor entry's
+// custom_regs: lamp (0x03), infrared (0x37) and the pixel clocks (0xa5/0xab).
+bool gl128_is_per_pass_reg(std::uint16_t address)
+{
+    return address == REG_0x03 || address == REG_IR || address == 0xA5 || address == 0xAB;
+}
+
+// Image-pass pixel clock (0xa5 and 0xab) of a sensor entry.
+unsigned gl128_pixel_clock(const Genesys_Sensor& sensor)
+{
+    return sensor.custom_regs.get_value(0xA5);
+}
+
+} // namespace
+
+unsigned gl128_asic_dpi(const Genesys_Sensor& sensor)
+{
+    return sensor.register_dpiset * 6;
+}
+
+unsigned gl128_host_downsample(const Genesys_Sensor& sensor, unsigned xres)
+{
+    return std::max(1u, gl128_asic_dpi(sensor) / xres);
+}
+
+namespace {
+
+// Like Genesys_Register_Set::set16()/set24() (MSB first), but adding the
+// registers if the set does not hold them yet.
+void gl128_init_reg16(Genesys_Register_Set* reg, std::uint16_t address, std::uint16_t value)
+{
+    reg->init_reg(address, static_cast<std::uint8_t>((value >> 8) & 0xff));
+    reg->init_reg(static_cast<std::uint16_t>(address + 1), static_cast<std::uint8_t>(value & 0xff));
+}
+
+void gl128_init_reg24(Genesys_Register_Set* reg, std::uint16_t address, std::uint32_t value)
+{
+    reg->init_reg(address, static_cast<std::uint8_t>((value >> 16) & 0xff));
+    reg->init_reg(static_cast<std::uint16_t>(address + 1),
+                  static_cast<std::uint8_t>((value >> 8) & 0xff));
+    reg->init_reg(static_cast<std::uint16_t>(address + 2), static_cast<std::uint8_t>(value & 0xff));
+}
+
+
+} // namespace
+
+// --- AFE strip helpers ----------------------------------------------------
+// Used by gl128_run_asic_shading() for the AFE probe and relight strips.
+namespace {
+
+// Pixels of a stationary AFE strip (16-bit RGB), from the device tables.
+unsigned gl128_afe_strip_pixels(const Genesys_Device* dev, bool wide)
+{
+    const auto& t = gl128_device_tables(dev);
+    return (wide ? t.afe_wide_endpixel : t.afe_endpixel) - t.afe_strpixel;
+}
+
+// Mean R/G/B of a 16-bit LE strip, planar (RRR...GGG...BBB...) or
+// interleaved (RGBRGB...).
+std::array<double, 3> gl128_channel_means_u16(const std::vector<std::uint8_t>& strip,
+                                              unsigned pixels, bool planar)
+{
+    const std::size_t expected = static_cast<std::size_t>(pixels) * 3 * 2;
+    if (strip.size() < expected) {
+        throw SaneException("GL128: AFE strip too short: %zu < %zu",
+                            strip.size(), expected);
+    }
+    double sums[3] = {0.0, 0.0, 0.0};
+    if (planar) {
+        const std::size_t plane = static_cast<std::size_t>(pixels) * 2;
+        for (int c = 0; c < 3; c++) {
+            const std::size_t base = static_cast<std::size_t>(c) * plane;
+            for (unsigned i = 0; i < pixels; i++) {
+                std::size_t off = base + static_cast<std::size_t>(i) * 2;
+                sums[c] += static_cast<double>(strip[off] | (strip[off + 1] << 8));
+            }
+        }
+    } else {
+        for (unsigned i = 0; i < pixels; i++) {
+            std::size_t base = static_cast<std::size_t>(i) * 6;
+            for (int c = 0; c < 3; c++) {
+                std::size_t off = base + static_cast<std::size_t>(c) * 2;
+                sums[c] += static_cast<double>(strip[off] | (strip[off + 1] << 8));
+            }
+        }
+    }
+    return { sums[0] / pixels, sums[1] / pixels, sums[2] / pixels };
+}
+
+
+// Lamp control: single writes of 0x03. 0x37 (infrared LED) is written only at
+// boot, as SilverFast does for colour scans; infrared is not supported yet.
+void gl128_lamp_on(Genesys_Device* dev)
+{
+    // Also kept in dev->reg: sanei_genesys_set_lamp_power() modifies 0x03
+    // there and needs the register to exist.
+    std::uint8_t val = static_cast<std::uint8_t>(REG_0x03_XPASEL | REG_0x03_LAMPPWR);
+    dev->interface->write_register(REG_0x03, val);
+    dev->reg.init_reg(REG_0x03, val);
+}
+
+void gl128_lamp_off(Genesys_Device* dev)
+{
+    // Only 0x03, as SilverFast does before its dark strip (0x03=0x20). Also
+    // writing 0x37 kept the lamp lit through the dark strip.
+    dev->interface->write_register(REG_0x03, REG_0x03_XPASEL);
+    dev->reg.init_reg(REG_0x03, REG_0x03_XPASEL);
+}
+
+// Lamp control pulses on 0x03, one write every 1.5 ms as in SilverFast's
+// captures (each write there is followed by a status read). The lamp driver
+// keeps the state these pulses set until the next power cycle.
+void gl128_write_lamp_pulses(Genesys_Device* dev, std::initializer_list<std::uint8_t> values)
+{
+    bool first = true;
+    for (std::uint8_t v : values) {
+        if (!first) {
+            std::this_thread::sleep_for(std::chrono::microseconds(1500));
+        }
+        first = false;
+        dev->interface->write_register(REG_0x03, v);
+    }
+    dev->reg.init_reg(REG_0x03, *(values.end() - 1));
+}
+
+} // namespace
+
+// --- Stationary strips ------------------------------------------------------
+// Reading a strip without moving the carriage (AFE probes, dark reference).
+namespace {
+
+
+constexpr double GL128_STATIONARY_IDLE_WAIT_S = 2.0;
+constexpr int GL128_STATIONARY_START_RETRIES = 1;
+constexpr std::uint8_t GL128_CANCEL_REG01 = 0x22;
+
+// Status bytes seen in the captures when stationary data is ready.
+bool gl128_is_stationary_data_ready_code(std::uint8_t status_byte)
+{
+    return status_byte == 0xBD || status_byte == 0xA9 ||
+           status_byte == 0xAD || status_byte == 0x9C;
+}
+
+// Stationary AFE strip registers, motor off: the calibration window, DPISET,
+// clocks and line period of the device tables. The memory layout registers
+// (0xd0-0xf8) keep their asic_boot() values.
+void gl128_setup_afe_strip_regs(Genesys_Device* dev, const Genesys_Sensor& sensor, bool wide)
+{
+    const auto& t = gl128_device_tables(dev);
+
+    // Sensor registers, except lamp (0x03) and IR (0x37).
+    for (const auto& r : sensor.custom_regs) {
+        if (gl128_is_per_pass_reg(r.address)) {
+            continue;
+        }
+        dev->interface->write_register(r.address, static_cast<std::uint8_t>(r.value));
+    }
+
+    dev->interface->write_register(0x2B, static_cast<std::uint8_t>(t.afe_clocks.dummy));
+    dev->interface->write_register(0xA5, static_cast<std::uint8_t>(t.afe_clocks.clk_a));
+    dev->interface->write_register(0xAB, static_cast<std::uint8_t>(t.afe_clocks.clk_b));
+    dev->interface->write_register(0xA3, 0x01);
+
+    const unsigned end = wide ? t.afe_wide_endpixel : t.afe_endpixel;
+    gl128_init_reg24(&dev->reg, REG_LINCNT, 1);
+    gl128_init_reg16(&dev->reg, REG_DPISET, static_cast<std::uint16_t>(t.afe_dpiset));
+    gl128_init_reg24(&dev->reg, REG_STRPIXEL, t.afe_strpixel);
+    gl128_init_reg24(&dev->reg, REG_ENDPIXEL, end);
+    gl128_init_reg24(&dev->reg, REG_FEEDL, 1);
+    gl128_init_reg24(&dev->reg, REG_LPERIOD, t.afe_lperiod);
+    gl128_init_reg24(&dev->reg, REG_EXPOSURE, t.exposure);
+    dev->interface->write_register(REG_DEPTH_A, DEPTH16_A);
+    dev->interface->write_register(REG_DEPTH_B, DEPTH16_B);
+
+    // No motor: keep 0x02 clear of MTRPWR/AGOHOME/FASTFED.
+    dev->interface->write_register(REG_0x02, 0x00);
+    dev->reg.init_reg(REG_0x02, 0x00);
+
+    // SHDAREA, no SCAN yet (set by the start sequence).
+    std::uint8_t reg01 = dev->reg.get8(REG_0x01);
+    reg01 = (reg01 | REG_0x01_SHDAREA) & ~REG_0x01_SCAN & ~REG_0x01_DVDSET;
+    dev->interface->write_register(REG_0x01, reg01);
+    dev->reg.init_reg(REG_0x01, reg01);
+
+    // gl128_init_reg16/24() only update dev->reg; write the window out.
+    for (std::uint16_t addr : { REG_LINCNT, static_cast<std::uint16_t>(REG_LINCNT + 1),
+                                static_cast<std::uint16_t>(REG_LINCNT + 2),
+                                REG_DPISET, static_cast<std::uint16_t>(REG_DPISET + 1),
+                                REG_STRPIXEL, static_cast<std::uint16_t>(REG_STRPIXEL + 1),
+                                static_cast<std::uint16_t>(REG_STRPIXEL + 2),
+                                REG_ENDPIXEL, static_cast<std::uint16_t>(REG_ENDPIXEL + 1),
+                                static_cast<std::uint16_t>(REG_ENDPIXEL + 2),
+                                REG_FEEDL, static_cast<std::uint16_t>(REG_FEEDL + 1),
+                                static_cast<std::uint16_t>(REG_FEEDL + 2),
+                                REG_LPERIOD, static_cast<std::uint16_t>(REG_LPERIOD + 1),
+                                static_cast<std::uint16_t>(REG_LPERIOD + 2),
+                                REG_EXPOSURE, static_cast<std::uint16_t>(REG_EXPOSURE + 1),
+                                static_cast<std::uint16_t>(REG_EXPOSURE + 2) }) {
+        dev->interface->write_register(addr, dev->reg.get8(addr));
+    }
+}
+
+// Start sequence from the captures: motor off, CLRCNT, 0x01 written from the
+// cached value (a read-modify-write can pick up SCAN/DVDSET left by the
+// previous image pass, and then START never fills the buffer), START.
+void gl128_start_stationary_strip(Genesys_Device* dev)
+{
+    const std::uint8_t motor_mask = REG_0x02_MTRPWR | REG_0x02_AGOHOME | REG_0x02_FASTFED;
+    dev->interface->write_register(REG_0x02, 0x00);
+    std::uint8_t reg02 = dev->interface->read_register(REG_0x02);
+    if (reg02 & motor_mask) {
+        dev->interface->write_register(REG_0x02, 0x00);
+    }
+    dev->interface->write_register(REG_CLRCNT, CLRCNT_ALL);
+    std::uint8_t reg01 = (dev->reg.get8(REG_0x01) | REG_0x01_SHDAREA | REG_0x01_SCAN) &
+                         ~REG_0x01_DVDSET;
+    dev->interface->write_register(REG_0x01, reg01);
+    dev->reg.init_reg(REG_0x01, reg01);
+    dev->interface->write_register(REG_START, START_GO);
+}
+
+// Poll 0x101 until strip data is ready. Stationary: HOME and not BUFEMPTY,
+// or a known ready code (rejects motor-busy 0xa5, which lacks HOME).
+// Motorized (white strip): any not-BUFEMPTY, since the carriage leaves home.
+void gl128_wait_shading_data_ready(Genesys_Device* dev, double timeout_s, bool motorized,
+                                   const char* where)
+{
+    scanner_read_status(*dev);
+    auto deadline = std::chrono::steady_clock::now() +
+                    std::chrono::milliseconds(static_cast<long>(timeout_s * 1000));
+    std::uint8_t last = 0xff;
+    while (std::chrono::steady_clock::now() < deadline) {
+        Status status = scanner_read_status(*dev);
+        last = dev->interface->read_register(REG_STATUS);
+        if (motorized) {
+            if (!status.is_buffer_empty) {
+                return;
+            }
+        } else if (gl128_is_stationary_data_ready_code(last) ||
+                  (!status.is_buffer_empty && status.is_at_home)) {
+            return;
+        }
+        std::this_thread::sleep_for(std::chrono::milliseconds(10));
+    }
+    throw SaneException("GL128: %s: no %s data ready within %.0fs (last status=0x%02x)",
+                        where, motorized ? "motorized" : "stationary", timeout_s, last);
+}
+
+// Abort a leftover image SCAN so stationary geometry writes stick. A park
+// leaves 0x02 armed (MTRPWR|AGOHOME); the next stationary START with AGOHOME
+// still set hangs with status 0xcd. SCAN and motor bits are read back from
+// the hardware each poll, since dev->reg drops AGOHOME after a park.
+void gl128_reset_stationary_scan_engine(Genesys_Device* dev, const char* where)
+{
+    (void) where;
+    const std::uint8_t motor_mask = REG_0x02_MTRPWR | REG_0x02_AGOHOME | REG_0x02_FASTFED;
+    dev->interface->write_register(REG_START, 0x00);
+    dev->interface->write_register(REG_0x01, GL128_CANCEL_REG01);
+    dev->interface->write_register(REG_0x02, 0x00);
+    dev->interface->write_register(REG_CLRCNT, CLRCNT_ALL);
+
+    auto deadline = std::chrono::steady_clock::now() +
+                    std::chrono::milliseconds(
+                        static_cast<long>(GL128_STATIONARY_IDLE_WAIT_S * 1000));
+    std::uint8_t last01 = 0, last02 = 0;
+    while (std::chrono::steady_clock::now() < deadline) {
+        last01 = dev->interface->read_register(REG_0x01);
+        last02 = dev->interface->read_register(REG_0x02);
+        Status status = scanner_read_status(*dev);
+        bool scan_clear = (last01 & REG_0x01_SCAN) == 0;
+        bool motor_clear = (last02 & motor_mask) == 0;
+        bool idle = status.is_at_home && !status.is_motor_enabled;
+        if (scan_clear && motor_clear && idle) {
+            dev->reg.init_reg(REG_0x01, last01);
+            dev->reg.init_reg(REG_0x02, last02);
+            if (last01 & REG_0x01_DVDSET) {
+                std::uint8_t fixed = (last01 | REG_0x01_SHDAREA) & ~REG_0x01_SCAN &
+                                     ~REG_0x01_DVDSET;
+                dev->interface->write_register(REG_0x01, fixed);
+            }
+            return;
+        }
+        if (last01 & REG_0x01_SCAN) {
+            std::uint8_t fixed = (last01 | REG_0x01_SHDAREA) & ~REG_0x01_SCAN &
+                                 ~REG_0x01_DVDSET;
+            dev->interface->write_register(REG_0x01, fixed);
+        }
+        if (last02 & motor_mask) {
+            dev->interface->write_register(REG_0x02, 0x00);
+        }
+        std::this_thread::sleep_for(std::chrono::milliseconds(20));
+    }
+    // A timed-out reset is not fatal: the caller retries the strip.
+}
+
+// Read one stationary 16-bit AFE strip. Does not move the carriage.
+std::vector<std::uint8_t> gl128_acquire_afe_strip(Genesys_Device* dev,
+                                                  const Genesys_Sensor& sensor,
+                                                  bool wide)
+{
+    const std::size_t size = static_cast<std::size_t>(gl128_afe_strip_pixels(dev, wide)) * 6;
+    gl128_reset_stationary_scan_engine(dev, "AFE strip");
+    gl128_setup_afe_strip_regs(dev, sensor, wide);
+
+    bool started = false;
+    SaneException last_exc(SANE_STATUS_INVAL);
+    bool have_exc = false;
+    for (int attempt = 0; attempt <= GL128_STATIONARY_START_RETRIES; attempt++) {
+        if (attempt) {
+            gl128_reset_stationary_scan_engine(dev, "AFE strip retry");
+        }
+        gl128_start_stationary_strip(dev);
+        try {
+            gl128_wait_shading_data_ready(dev, 5.0, false, "AFE strip");
+            started = true;
+            break;
+        } catch (const SaneException& exc) {
+            last_exc = exc;
+            have_exc = true;
+            gl128_reset_stationary_scan_engine(dev, "AFE strip fail");
+        }
+    }
+    if (!started) {
+        if (have_exc) {
+            throw last_exc;
+        }
+        throw SaneException("GL128: AFE strip start failed");
+    }
+
+    std::vector<std::uint8_t> buf(size);
+    // addr is ignored: bulk_read_data_send_header() uses the AHB address
+    // 0x10000000 for GL124-family chips.
+    dev->interface->bulk_read_data(0, buf.data(), size);
+
+    std::uint8_t reg01 = dev->reg.get8(REG_0x01);
+    dev->interface->write_register(REG_0x01, static_cast<std::uint8_t>(reg01 & ~REG_0x01_SCAN));
+    dev->reg.init_reg(REG_0x01, static_cast<std::uint8_t>(reg01 & ~REG_0x01_SCAN));
+
+    return buf;
+}
+
+
+// Poll status until home and motor idle. Status is read twice: the first
+// read after an operation can still show the previous state.
+void gl128_wait_until_at_home(Genesys_Device* dev, double timeout_s)
+{
+    auto deadline = std::chrono::steady_clock::now() +
+                    std::chrono::milliseconds(static_cast<long>(timeout_s * 1000));
+    while (std::chrono::steady_clock::now() < deadline) {
+        scanner_read_status(*dev); // stale first read
+        Status status = scanner_read_status(*dev);
+        if (status.is_at_home && !status.is_motor_enabled) {
+            return;
+        }
+        std::this_thread::sleep_for(std::chrono::milliseconds(50));
+    }
+    throw SaneException("GL128: carriage did not reach home within %.0fs (AGOHOME park)",
+                        timeout_s);
+}
+
+// End or abort an image pass as SilverFast does. With AGOHOME armed: lamp
+// strobe, 0x01=0x22, second strobe, wait for the park (up to 60 s). Without
+// AGOHOME (e.g. a feed timeout): clear SCAN only; no capture shows a
+// mid-feed abort.
+void gl128_stop_motor(Genesys_Device* dev)
+{
+    static constexpr std::uint8_t CANCEL_LAMP_PRE[] = { 0x30, 0x20 };
+    static constexpr std::uint8_t CANCEL_LAMP_POST[] = { 0x10, 0x00, 0x20, 0x30, 0x20, 0x30 };
+    static constexpr std::uint8_t CANCEL_REG01 = 0x22;
+
+    std::uint8_t reg02 = dev->reg.get8(REG_0x02);
+    if (reg02 & REG_0x02_AGOHOME) {
+        for (std::uint8_t v : CANCEL_LAMP_PRE) {
+            dev->interface->write_register(REG_0x03, v);
+        }
+        dev->interface->write_register(REG_0x01, CANCEL_REG01);
+        dev->reg.init_reg(REG_0x01, CANCEL_REG01);
+        for (std::uint8_t v : CANCEL_LAMP_POST) {
+            dev->interface->write_register(REG_0x03, v);
+        }
+        // The captures leave 0x02 alone after a cancel. Dropping AGOHOME from
+        // dev->reg stops a second call (end_scan(), then sane_close()) from
+        // strobing and waiting again.
+        gl128_wait_until_at_home(dev, 60.0);
+        dev->reg.init_reg(REG_0x02, static_cast<std::uint8_t>(reg02 & ~REG_0x02_AGOHOME));
+    } else {
+        std::uint8_t reg01 = dev->reg.get8(REG_0x01);
+        reg01 = static_cast<std::uint8_t>(reg01 & ~REG_0x01_SCAN);
+        dev->interface->write_register(REG_0x01, reg01);
+        dev->reg.init_reg(REG_0x01, reg01);
+    }
+}
+
+// Line timing for a sensor entry; width_native = ENDPIXEL - STRPIXEL (7200
+// dpi units). LPERIOD, dummy and pixel clocks come from the sensor entry
+// (tables_sensor.cpp), overridden by the device tables' width programs and
+// dark-strip clocks.
+Gl128Timing gl128_timing(const Gl128DeviceTables& tables, const Genesys_Sensor& sensor,
+                         unsigned width_native)
+{
+    const unsigned asic_dpi = gl128_asic_dpi(sensor);
+    // A window uses the narrowest width program at least as wide as itself;
+    // wider windows use the sensor entry (verified on hardware at 36.58 mm).
+    if (asic_dpi == tables.width_program_dpi) {
+        for (const auto& p : tables.width_programs) {
+            if (width_native <= p.max_width) {
+                return p.timing;
+            }
+        }
+    }
+
+    const unsigned clock = gl128_pixel_clock(sensor);
+    const Gl128PassClocks image{ static_cast<unsigned>(sensor.dummy_pixel), clock, clock };
+    Gl128Timing t{ static_cast<unsigned>(sensor.exposure_lperiod), image, image, image };
+    for (const auto& d : tables.dark_clocks) {
+        if (d.asic_dpi == asic_dpi) {
+            t.dark = d.clocks;
+        }
+    }
+    return t;
+}
+
+// Registers for genesys' host-side shading passes, built into `regs` only:
+// genesys_shading_calibration_impl() copies dev->reg into its local set before
+// calling init_regs_for_shading() and writes that set out afterwards.
+// Window, DPISET and LPERIOD of the image scan, FEEDL 1, SHDAREA (SCAN is set
+// by begin_scan()), as in SilverFast's shading passes.
+void gl128_setup_shading_strip_regs(const Gl128DeviceTables& tables, const Genesys_Sensor& sensor,
+                                    const ScanSession& real_session,
+                                    unsigned lincnt, Genesys_Register_Set& regs)
+{
+    for (const auto& r : sensor.custom_regs) {
+        if (gl128_is_per_pass_reg(r.address)) {
+            continue;
+        }
+        regs.init_reg(r.address, static_cast<std::uint8_t>(r.value));
+    }
+    const Gl128Timing timing = gl128_timing(tables, sensor,
+                                           real_session.pixel_endx - real_session.pixel_startx);
+    regs.init_reg(0x2B, static_cast<std::uint8_t>(timing.image.dummy));
+    regs.init_reg(0xA5, static_cast<std::uint8_t>(timing.image.clk_a));
+    regs.init_reg(0xAB, static_cast<std::uint8_t>(timing.image.clk_b));
+
+    gl128_init_reg24(&regs, REG_LINCNT, lincnt);
+    gl128_init_reg16(&regs, REG_DPISET, static_cast<std::uint16_t>(sensor.register_dpiset));
+    gl128_init_reg24(&regs, REG_STRPIXEL, real_session.pixel_startx);
+    gl128_init_reg24(&regs, REG_ENDPIXEL, real_session.pixel_endx);
+    gl128_init_reg24(&regs, REG_FEEDL, 1);
+    gl128_init_reg24(&regs, REG_LPERIOD, timing.lperiod);
+    gl128_init_reg24(&regs, REG_EXPOSURE, tables.exposure);
+    // Same depth registers as the image pass (chunky 16-bit RGB), so genesys
+    // can average the data as interleaved RGB. SilverFast's DEPTH16 setting
+    // returns planar lines.
+    regs.init_reg(REG_DEPTH_A, DEPTH8_A);
+    regs.init_reg(REG_DEPTH_B, DEPTH8_B);
+
+    // Motor off: both passes are stationary here (see begin_scan()).
+    regs.init_reg(REG_0x02, 0x00);
+    regs.init_reg(REG_0x01, static_cast<std::uint8_t>(REG_0x01_SHDAREA));
+}
+
+
+// --- Motor slope and channel exposure tables (AHB) --------------------------
+// A slope table (from the motor entry) goes to both 0x1000c000 (scan) and
+// 0x10010000 (fast); one exposure table goes to each of 0x10000000/0x10004000/
+// 0x10008000 (R/G/B). Without a slope table the motor has no ramp and does
+// not advance.
+constexpr std::uint32_t GL128_AHB_CHANNEL_R = 0x10000000;
+constexpr std::uint32_t GL128_AHB_CHANNEL_G = 0x10004000;
+constexpr std::uint32_t GL128_AHB_CHANNEL_B = 0x10008000;
+constexpr std::uint32_t GL128_AHB_SLOPE_SCAN = 0x1000c000;
+constexpr std::uint32_t GL128_AHB_SLOPE_FAST = 0x10010000;
+
+void gl128_upload_image_tables(Genesys_Device* dev, unsigned asic_dpi)
+{
+    // Per-channel exposure table: 256 u16 words of exposure / (7200 /
+    // asic_dpi), entry 0 from the device tables.
+    const auto& t = gl128_device_tables(dev);
+    const unsigned oversample = std::max(1u, 7200u / asic_dpi);
+    const unsigned body = t.exposure / oversample;
+    const unsigned first = asic_dpi == t.channel_first_override_dpi
+            ? t.channel_first_override : body + t.channel_first_extra;
+    if (first > 0xffff) {
+        throw SaneException("GL128: channel exposure %u does not fit 16 bits", first);
+    }
+    std::vector<std::uint8_t> expo(512);
+    for (unsigned k = 0; k < 256; k++) {
+        unsigned v = (k == 0) ? first : body;
+        expo[k * 2] = static_cast<std::uint8_t>(v & 0xff);
+        expo[k * 2 + 1] = static_cast<std::uint8_t>((v >> 8) & 0xff);
+    }
+    // No slope upload here: the fast ramp from the second positioning feed
+    // stays in place for the image pass, as in the capture.
+    for (std::uint32_t addr : { GL128_AHB_CHANNEL_R, GL128_AHB_CHANNEL_G, GL128_AHB_CHANNEL_B }) {
+        dev->interface->write_ahb(addr, expo.size(), expo.data());
+    }
+}
+
+// --- Positioning feed pair (from home to the scan-start line) --------------
+// Replayed from the SilverFast capture (600 dpi):
+//   feed 1: FEEDL 28292, slow slope, done when 0x21 reads 0x04
+//   feed 2: FEEDL 13128 (top of the window), fast slope, done via 0x101
+// Each slope goes to both slope slots. START is 0x0f=01 alone (no 0x0d
+// counter clear). An image START at home with MOTORENB set hangs with
+// status 0xcd.
+
+// The second feed runs from the top of the window (feed2_steps) towards its
+// end (window_end_steps) in proportion to tl_y / window_height_mm (pyopticfilm
+// feed_to_scan_steps_for_area()). A SilverFast lower-half crop at 1800 dpi
+// used 20232, all other registers unchanged.
+unsigned gl128_feed2_steps(const Genesys_Device* dev)
+{
+    const auto& t = gl128_device_tables(dev);
+    const float y_size = t.window_height_mm;
+    float y1 = y_size > 0.0f ? dev->settings.tl_y / y_size : 0.0f;
+    y1 = std::max(0.0f, std::min(1.0f, y1));
+    return static_cast<unsigned>(lround(t.feed2_steps +
+            y1 * static_cast<float>(t.window_end_steps - t.feed2_steps)));
+}
+
+std::uint8_t gl128_read_feed_probe(Genesys_Device* dev)
+{
+    // read_request_register(0x21): bRequest=0x0c, wValue=0x8e, wIndex=0x21.
+    std::uint8_t val = 0;
+    dev->interface->get_usb_device().control_msg(REQUEST_TYPE_IN, REQUEST_REGISTER,
+                                                 VALUE_GET_REGISTER, 0x21, 1, &val);
+    return val;
+}
+
+Status gl128_read_status_reliable(Genesys_Device* dev)
+{
+    scanner_read_status(*dev); // the first read can be stale
+    return scanner_read_status(*dev);
+}
+
+// Uploads a slope table of the motor entry (tables_motor.cpp) to both slope
+// slots, 16-bit little endian.
+void gl128_upload_slope(Genesys_Device* dev, const MotorProfile& profile)
+{
+    const auto& table = profile.slope.table;
+    if (table.empty()) {
+        throw SaneException("GL128: the motor profile has no slope table");
+    }
+    std::vector<std::uint8_t> slope;
+    slope.reserve(table.size() * 2);
+    for (std::uint16_t w : table) {
+        slope.push_back(static_cast<std::uint8_t>(w & 0xff));
+        slope.push_back(static_cast<std::uint8_t>(w >> 8));
+    }
+    dev->interface->write_ahb(GL128_AHB_SLOPE_SCAN, slope.size(), slope.data());
+    dev->interface->write_ahb(GL128_AHB_SLOPE_FAST, slope.size(), slope.data());
+}
+
+const MotorProfile& gl128_fast_motor_profile(const Genesys_Device* dev)
+{
+    if (dev->motor.fast_profiles.empty()) {
+        throw SaneException("GL128: the motor has no fast profile");
+    }
+    return dev->motor.fast_profiles.front();
+}
+
+const MotorProfile& gl128_slow_motor_profile(const Genesys_Device* dev)
+{
+    if (dev->motor.profiles.empty()) {
+        throw SaneException("GL128: the motor has no profile");
+    }
+    return dev->motor.profiles.front();
+}
+
+void gl128_write_feedl(Genesys_Device* dev, unsigned steps)
+{
+    dev->interface->write_register(REG_FEEDL, static_cast<std::uint8_t>((steps >> 16) & 0xff));
+    dev->interface->write_register(REG_FEEDL + 1, static_cast<std::uint8_t>((steps >> 8) & 0xff));
+    dev->interface->write_register(REG_FEEDL + 2, static_cast<std::uint8_t>(steps & 0xff));
+}
+
+// Wait for a feed: first MOTORENB, then after a minimum run time 0x21 == 0x04
+// or FEEDFSH with MOTORENB clear.
+void gl128_wait_feed_done(Genesys_Device* dev, unsigned steps, double timeout_s)
+{
+    const double expected_s =
+            1.0 * (static_cast<double>(steps) / gl128_device_tables(dev).feed1_steps) * 0.9;
+    const double min_motion_s = std::min(0.25, std::max(0.05, expected_s));
+    const auto t0 = std::chrono::steady_clock::now();
+    const auto deadline = t0 + std::chrono::milliseconds(static_cast<long>(timeout_s * 1000));
+    bool motion_seen = false;
+    auto motion_t = t0;
+    while (std::chrono::steady_clock::now() < deadline) {
+        std::uint8_t probe = gl128_read_feed_probe(dev);
+        Status st = gl128_read_status_reliable(dev);
+        if (!motion_seen) {
+            if (st.is_motor_enabled) {
+                motion_seen = true;
+                motion_t = std::chrono::steady_clock::now();
+            }
+        } else {
+            double moved = std::chrono::duration<double>(
+                    std::chrono::steady_clock::now() - motion_t).count();
+            if (moved >= min_motion_s &&
+                (probe == 0x04 || (st.is_feeding_finished && !st.is_motor_enabled)))
+            {
+                return;
+            }
+        }
+        std::this_thread::sleep_for(std::chrono::milliseconds(50));
+    }
+    // Timeout: clear SCAN and drop motor power (no AGOHOME park).
+    std::uint8_t r01 = dev->interface->read_register(REG_0x01);
+    dev->interface->write_register(REG_0x01, static_cast<std::uint8_t>(r01 & ~REG_0x01_SCAN));
+    std::uint8_t r02 = dev->interface->read_register(REG_0x02);
+    dev->interface->write_register(REG_0x02, static_cast<std::uint8_t>(r02 & ~REG_0x02_MTRPWR));
+    throw SaneException("GL128: feed of %u steps did not finish within %.0fs (motion seen: %s)",
+                        steps, timeout_s, motion_seen ? "yes" : "no");
+}
+
+// --- ASIC (hardware) shading -------------------------------------------------
+// The ASIC applies an uploaded dark/gain table to the image when 0x01 has
+// DVDSET, as SilverFast does; genesys' host-side correction is disabled for
+// this model.
+
+constexpr std::uint32_t GL128_AHB_SHADING = 0x10014000;
+constexpr unsigned GL128_SHADING_LINES = 128;
+constexpr unsigned GL128_SHADING_BLOCK_DATA_PAIRS = 126;
+constexpr unsigned GL128_SHADING_BLOCK_PAD_PAIRS = 2;   // 128 pairs per 512-byte block
+constexpr unsigned GL128_SHADING_GAIN_UNITY = 0x2000;
+constexpr unsigned GL128_SHADING_GAIN_TARGET = 0xFFFF;
+constexpr unsigned GL128_SHADING_GAIN_MIN = GL128_SHADING_GAIN_UNITY / 4;
+constexpr unsigned GL128_SHADING_GAIN_MAX = GL128_SHADING_GAIN_UNITY * 4;
+
+using Gl128Rgb = std::array<unsigned, 3>;
+
+unsigned gl128_declared_shading_size(unsigned entries)
+{
+    unsigned data = entries * 3;
+    return 4 * (data + GL128_SHADING_BLOCK_PAD_PAIRS * (data / GL128_SHADING_BLOCK_DATA_PAIRS));
+}
+
+// Table layout: (dark, gain) u16 LE pairs per pixel and channel, two
+// (last dark, 0) pad pairs after every 126 data pairs, zero-filled tail.
+std::vector<std::uint8_t> gl128_pack_shading_table(const std::vector<Gl128Rgb>& dark,
+                                                   const std::vector<Gl128Rgb>& gain,
+                                                   unsigned declared_size)
+{
+    std::vector<std::uint8_t> out;
+    auto put16 = [&out](unsigned v) {
+        out.push_back(static_cast<std::uint8_t>(v & 0xff));
+        out.push_back(static_cast<std::uint8_t>((v >> 8) & 0xff));
+    };
+    unsigned pairs = 0;
+    unsigned last_dark = 0;
+    for (std::size_t i = 0; i < dark.size(); i++) {
+        for (int c = 0; c < 3; c++) {
+            if (pairs && pairs % GL128_SHADING_BLOCK_DATA_PAIRS == 0) {
+                for (unsigned k = 0; k < GL128_SHADING_BLOCK_PAD_PAIRS; k++) {
+                    put16(last_dark);
+                    put16(0);
+                }
+            }
+            last_dark = dark[i][c] & 0xffff;
+            put16(last_dark);
+            put16(gain[i][c] & 0xffff);
+            pairs++;
+        }
+    }
+    if (out.size() > declared_size) {
+        throw SaneException("GL128: shading payload %zu exceeds declared size %u",
+                            out.size(), declared_size);
+    }
+    out.resize(declared_size, 0);
+    return out;
+}
+
+// Dark level per column parity. The CCD's two staggered rows have their own
+// dark level: SilverFast's 7200 dpi shading tables hold one value per channel
+// and parity (even 800/979/895, odd 1134/1285/1221), the even and odd column
+// means of its dark strip. A single mean leaves vertical stripes in the
+// shadows at 1440/2400/7200, where output columns alternate between the rows.
+std::vector<Gl128Rgb> gl128_parity_dark(const std::vector<Gl128Rgb>& dark)
+{
+    double acc[2][3] = {};
+    std::size_t n[2] = { 0, 0 };
+    for (std::size_t x = 0; x < dark.size(); x++) {
+        for (int c = 0; c < 3; c++) {
+            acc[x % 2][c] += dark[x][c];
+        }
+        n[x % 2]++;
+    }
+    Gl128Rgb mean[2]{};
+    for (int p = 0; p < 2; p++) {
+        const std::size_t count = n[p] ? n[p] : n[1 - p];
+        const double* sum = n[p] ? acc[p] : acc[1 - p];
+        for (int c = 0; c < 3; c++) {
+            mean[p][c] = static_cast<unsigned>(lround(sum[c] / std::max<std::size_t>(1, count)));
+        }
+    }
+    std::vector<Gl128Rgb> out(dark.size());
+    for (std::size_t x = 0; x < dark.size(); x++) {
+        out[x] = mean[x % 2];
+    }
+    return out;
+}
+
+// Column means of chunky 16-bit RGB strip data.
+std::vector<Gl128Rgb> gl128_average_columns_chunky(const std::vector<std::uint8_t>& raw,
+                                                   unsigned pixels, unsigned lines)
+{
+    std::vector<double> sums(pixels * 3, 0.0);
+    const std::size_t row = static_cast<std::size_t>(pixels) * 6;
+    for (unsigned y = 0; y < lines; y++) {
+        for (unsigned x = 0; x < pixels; x++) {
+            for (int c = 0; c < 3; c++) {
+                std::size_t off = y * row + x * 6 + c * 2;
+                sums[x * 3 + c] += raw[off] | (raw[off + 1] << 8);
+            }
+        }
+    }
+    std::vector<Gl128Rgb> out(pixels);
+    for (unsigned x = 0; x < pixels; x++) {
+        for (int c = 0; c < 3; c++) {
+            out[x][c] = static_cast<unsigned>(lround(sums[x * 3 + c] / lines));
+        }
+    }
+    return out;
+}
+
+unsigned gl128_shading_gain_for_white(unsigned white_unity)
+{
+    double denom = std::max(1.0, static_cast<double>(white_unity));
+    long gain = lround(static_cast<double>(GL128_SHADING_GAIN_TARGET) * GL128_SHADING_GAIN_UNITY /
+                       denom);
+    gain = std::max<long>(GL128_SHADING_GAIN_MIN, std::min<long>(GL128_SHADING_GAIN_MAX, gain));
+    return static_cast<unsigned>(gain);
+}
+
+struct Gl128ShadingWindow {
+    unsigned strpixel;
+    unsigned endpixel;
+    unsigned dpiset;
+    unsigned asic_dpi;
+    unsigned pixels;
+    Gl128Timing timing;
+};
+
+// Dark strip: stationary, lamp off. White strip: DVDSET, motor powered.
+std::vector<std::uint8_t> gl128_acquire_shading_strip(Genesys_Device* dev,
+                                                      const Gl128ShadingWindow& w, bool dvdset)
+{
+    const Gl128PassClocks& clocks = dvdset ? w.timing.white : w.timing.dark;
+    if (!dvdset) {
+        gl128_reset_stationary_scan_engine(dev, "shading strip");
+    }
+    dev->interface->write_register(0x2B, static_cast<std::uint8_t>(clocks.dummy));
+    dev->interface->write_register(0xA5, static_cast<std::uint8_t>(clocks.clk_a));
+    dev->interface->write_register(0xAB, static_cast<std::uint8_t>(clocks.clk_b));
+    auto w24 = [dev](std::uint16_t a, unsigned v) {
+        dev->interface->write_register(a, static_cast<std::uint8_t>((v >> 16) & 0xff));
+        dev->interface->write_register(a + 1, static_cast<std::uint8_t>((v >> 8) & 0xff));
+        dev->interface->write_register(a + 2, static_cast<std::uint8_t>(v & 0xff));
+    };
+    w24(REG_LINCNT, GL128_SHADING_LINES);
+    dev->interface->write_register(REG_DPISET, static_cast<std::uint8_t>((w.dpiset >> 8) & 0xff));
+    dev->interface->write_register(REG_DPISET + 1, static_cast<std::uint8_t>(w.dpiset & 0xff));
+    w24(REG_STRPIXEL, w.strpixel);
+    w24(REG_ENDPIXEL, w.endpixel);
+    w24(REG_FEEDL, 1);
+    w24(REG_LPERIOD, w.timing.lperiod);
+    w24(REG_EXPOSURE, gl128_device_tables(dev).exposure);
+    dev->interface->write_register(REG_DEPTH_A, DEPTH16_A);
+    dev->interface->write_register(REG_DEPTH_B, DEPTH16_B);
+
+    std::uint8_t reg01;
+    if (dvdset) {
+        // As SilverFast: 0x02=0x10 (MTRPWR, no AGOHOME). The carriage stays
+        // out (status 0xd4) and the positioning feeds start from there. An
+        // AGOHOME park here left the motor unable to feed on cold starts.
+        dev->interface->write_register(REG_0x02, static_cast<std::uint8_t>(REG_0x02_MTRPWR));
+        dev->interface->write_register(0x3B, 0x00);
+        dev->interface->write_register(0xA3, 0x00);
+        reg01 = static_cast<std::uint8_t>((0x22 | REG_0x01_SHDAREA | REG_0x01_DVDSET) &
+                                          ~REG_0x01_SCAN);
+    } else {
+        dev->interface->write_register(REG_0x02, 0x00);
+        dev->interface->write_register(0xA3, 0x01);
+        reg01 = static_cast<std::uint8_t>((0x22 | REG_0x01_SHDAREA) & ~REG_0x01_SCAN &
+                                          ~REG_0x01_DVDSET);
+    }
+    dev->interface->write_register(REG_0x01, reg01);
+
+    dev->interface->write_register(REG_CLRCNT, CLRCNT_ALL);
+    reg01 = static_cast<std::uint8_t>(reg01 | REG_0x01_SCAN);
+    dev->interface->write_register(REG_0x01, reg01);
+    dev->interface->write_register(REG_START, START_GO);
+    try {
+        gl128_wait_shading_data_ready(dev, 30.0, dvdset, "shading strip");
+    } catch (...) {
+        dev->interface->write_register(REG_0x01, static_cast<std::uint8_t>(reg01 & ~REG_0x01_SCAN));
+        if (dvdset) {
+            dev->interface->write_register(REG_0x02, 0x00);
+        }
+        throw;
+    }
+    const std::size_t size = static_cast<std::size_t>(w.pixels) * GL128_SHADING_LINES * 6;
+    std::vector<std::uint8_t> buf(size);
+    dev->interface->bulk_read_data(0, buf.data(), size);
+
+    // Clear SCAN, then drop motor power (SilverFast: status d4, no park).
+    dev->interface->write_register(REG_0x01, static_cast<std::uint8_t>(reg01 & ~REG_0x01_SCAN));
+    dev->interface->write_register(REG_0x02, 0x00);
+    return buf;
+}
+
+// ASIC shading for a colour scan: AFE probes, dark strip, unity table, lamp
+// on, white strip, measured table. The carriage must be at home.
+void gl128_run_asic_shading(Genesys_Device* dev, const Genesys_Sensor& sensor,
+                            const Gl128ShadingWindow& w)
+{
+    DBG_HELPER(dbg);
+    Status st = gl128_read_status_reliable(dev);
+    if (!st.is_at_home) {
+        throw SaneException("GL128 ASIC shading: carriage is not at home. "
+                            "Power-cycle, then retry.");
+    }
+    // Clock/timing registers first, same values for shading, feeds and image.
+    for (const auto& r : sensor.custom_regs) {
+        if (gl128_is_per_pass_reg(r.address)) {
+            continue;
+        }
+        dev->interface->write_register(r.address, static_cast<std::uint8_t>(r.value));
+        dev->reg.init_reg(r.address, static_cast<std::uint8_t>(r.value));
+    }
+
+    // Second lamp pulse train, once per boot. In SilverFast's USB captures its
+    // second register pass writes 0x03=0x20 and 0x33=0x04, then the AFE boot
+    // values, then it reads registers for 0.19 s and writes 0x03 = 0x00, 0x20,
+    // 0x20, 0x30, 0x20, 0x30 before its first strip (all four captures).
+    if (dev->lamp_boot_sequence_pending) {
+        dev->interface->write_register(REG_0x03, REG_0x03_XPASEL);
+        dev->interface->write_register(REG_DEPTH_A, DEPTH16_A);
+        dev->cmd_set->set_fe(dev, sensor, AFE_INIT);
+        std::this_thread::sleep_for(std::chrono::milliseconds(190));
+        dev->interface->write_register(REG_0x03, 0x00);
+        std::this_thread::sleep_for(std::chrono::microseconds(2300));
+        gl128_write_lamp_pulses(dev, { 0x20, 0x20, 0x30, 0x20, 0x30 });
+        dev->lamp_boot_sequence_pending = false;
+    }
+    const unsigned declared = gl128_declared_shading_size(w.pixels);
+
+    // Sequence, order and front-end codes as in SilverFast's 1800 dpi capture.
+    auto apply_fe = [&](std::array<int, 3> offs, std::array<int, 3> gains) {
+        for (int c = 0; c < 3; c++) {
+            dev->frontend.set_offset(c, static_cast<std::uint16_t>(offs[c]));
+            dev->frontend.set_gain(c, static_cast<std::uint16_t>(gains[c]));
+        }
+        dev->cmd_set->set_fe(dev, sensor, AFE_SET);
+    };
+    const auto& t = gl128_device_tables(dev);
+    const std::array<int, 3>& level_offs = t.shading_offsets;
+
+    // Cold start: the lamp needs to warm up, or the white strip (62 ms after
+    // switching on, as SilverFast) reads 0. Read stationary lamp-on strips
+    // once a second until the brightest channel changes < 1% over three
+    // readings (at least 5 s, at most 60 s).
+    if (dev->lamp_warmup_pending) {
+        gl128_lamp_on(dev);
+        apply_fe(level_offs, t.lamp_gains);
+        double prev = 0.0;
+        int stable = 0;
+        for (int i = 0; i < 60; i++) {
+            std::this_thread::sleep_for(std::chrono::seconds(1));
+            auto strip = gl128_acquire_afe_strip(dev, sensor, false);
+            auto m = gl128_channel_means_u16(strip, gl128_afe_strip_pixels(dev, false), true);
+            double peak = std::max({ m[0], m[1], m[2] });
+            DBG(DBG_info, "GL128 cold lamp warm-up %ds: peak=%.0f\n", i + 1, peak);
+            stable = (prev > 0.0 && std::abs(peak - prev) < 0.01 * peak) ? stable + 1 : 0;
+            prev = peak;
+            if (i >= 4 && stable >= 3) {
+                break;
+            }
+        }
+        dev->lamp_warmup_pending = false;
+    }
+
+    // Fast slope to both slope slots, then calibration exposure tables
+    // (entries 0 and 1 = the exposure, rest 0) to R/G/B.
+    gl128_upload_slope(dev, gl128_fast_motor_profile(dev));
+    {
+        std::vector<std::uint8_t> cal(512, 0);
+        for (int k = 0; k < 2; k++) {
+            cal[k * 2] = static_cast<std::uint8_t>(t.exposure & 0xff);
+            cal[k * 2 + 1] = static_cast<std::uint8_t>((t.exposure >> 8) & 0xff);
+        }
+        for (std::uint32_t addr : { GL128_AHB_CHANNEL_R, GL128_AHB_CHANNEL_G,
+                                    GL128_AHB_CHANNEL_B }) {
+            dev->interface->write_ahb(addr, cal.size(), cal.data());
+        }
+    }
+
+    // AFE probes with the lamp on (0x03=0x30), one strip each (one of them
+    // over the full width), then the after-probe gains.
+    gl128_lamp_on(dev);
+    // GPO 0xa7 and 0xa9 are 1 for the probes and both strips; the feed
+    // registers set them back to 0.
+    dev->interface->write_register(0xA7, 0x01);
+    dev->interface->write_register(0xA9, 0x01);
+    // The probe means are logged; on the 8200i SE they match SilverFast's own
+    // probes (its 7200 dpi capture: 17916/26915/27464 and 20026/29301/29962
+    // for the first two) when the clock set-up is right.
+    for (std::size_t i = 0; i < t.probes.size(); i++) {
+        const auto& p = t.probes[i];
+        apply_fe(p.offsets, p.gains);
+        if (i == t.wide_probe_index) {
+            gl128_acquire_afe_strip(dev, sensor, true);
+            continue;
+        }
+        auto strip = gl128_acquire_afe_strip(dev, sensor, false);
+        auto m = gl128_channel_means_u16(strip, gl128_afe_strip_pixels(dev, false), true);
+        DBG(DBG_info, "GL128 AFE probe offsets (%d,%d,%d) gains (%d,%d,%d): "
+            "means=(%.0f,%.0f,%.0f)\n",
+            p.offsets[0], p.offsets[1], p.offsets[2], p.gains[0], p.gains[1], p.gains[2],
+            m[0], m[1], m[2]);
+    }
+    apply_fe(level_offs, t.after_probe_gains);
+
+    // Lamp off (0x03=0x20); the dark strip starts 0.34 s later.
+    gl128_lamp_off(dev);
+    std::this_thread::sleep_for(std::chrono::milliseconds(340));
+    apply_fe(level_offs, t.dark_gains);
+    auto dark_raw = gl128_acquire_shading_strip(dev, w, false);
+    auto dark = gl128_average_columns_chunky(dark_raw, w.pixels, GL128_SHADING_LINES);
+    auto dark_flat = gl128_parity_dark(dark);
+    DBG(DBG_info, "GL128 shading dark even=(%u,%u,%u) odd=(%u,%u,%u)\n",
+        dark_flat[0][0], dark_flat[0][1], dark_flat[0][2],
+        dark_flat[dark_flat.size() > 1 ? 1 : 0][0], dark_flat[dark_flat.size() > 1 ? 1 : 0][1],
+        dark_flat[dark_flat.size() > 1 ? 1 : 0][2]);
+
+    // Unity table, lamp on, lamp gains, image exposure tables, white strip.
+    std::vector<Gl128Rgb> unity_gain(w.pixels, Gl128Rgb{ GL128_SHADING_GAIN_UNITY,
+                                                          GL128_SHADING_GAIN_UNITY,
+                                                          GL128_SHADING_GAIN_UNITY });
+    auto unity = gl128_pack_shading_table(dark_flat, unity_gain, declared);
+
+    // Wait for the lamp before the white strip. SilverFast starts it 62 ms
+    // after switching the lamp on, but after a power cycle the lamp is not
+    // lit that soon and the white strip reads <= dark. Read stationary strips
+    // until lit and steady (< 2%), at most 10 s. The unity table is uploaded
+    // afterwards, since strip data lands in the same AHB RAM.
+    gl128_lamp_on(dev);
+    apply_fe(level_offs, t.lamp_gains);
+    {
+        double prev = 0.0;
+        for (int i = 0; i < 20; i++) {
+            auto strip = gl128_acquire_afe_strip(dev, sensor, false);
+            auto m = gl128_channel_means_u16(strip, gl128_afe_strip_pixels(dev, false), true);
+            double peak = std::max({ m[0], m[1], m[2] });
+            DBG(DBG_info, "GL128 relight %d: peak=%.0f\n", i, peak);
+            if (peak > 30000.0 && prev > 0.0 && std::abs(peak - prev) < 0.02 * peak) {
+                break;
+            }
+            prev = peak;
+            std::this_thread::sleep_for(std::chrono::milliseconds(500));
+        }
+        gl128_reset_stationary_scan_engine(dev, "post relight");
+    }
+    dev->interface->write_ahb(GL128_AHB_SHADING, unity.size(), unity.data());
+    const std::array<int, 3>& white_gains = t.lamp_gains;
+    apply_fe(level_offs, white_gains);
+    gl128_upload_image_tables(dev, w.asic_dpi);
+    auto white_raw = gl128_acquire_shading_strip(dev, w, true);
+    auto white = gl128_average_columns_chunky(white_raw, w.pixels, GL128_SHADING_LINES);
+
+    std::vector<Gl128Rgb> gains(w.pixels);
+    for (unsigned x = 0; x < w.pixels; x++) {
+        for (int c = 0; c < 3; c++) {
+            gains[x][c] = gl128_shading_gain_for_white(white[x][c]);
+        }
+    }
+    DBG(DBG_info, "GL128 shading white0=(%u,%u,%u) gain0=(%u,%u,%u)\n",
+        white[0][0], white[0][1], white[0][2], gains[0][0], gains[0][1], gains[0][2]);
+    {
+        // White strip per channel, and the columns whose raw level (white
+        // plus the subtracted dark) is at the 16-bit ADC ceiling.
+        for (int c = 0; c < 3; c++) {
+            unsigned lo = 0xffff, hi = 0, at_ceiling = 0;
+            double sum = 0.0;
+            for (unsigned x = 0; x < w.pixels; x++) {
+                lo = std::min(lo, white[x][c]);
+                hi = std::max(hi, white[x][c]);
+                sum += white[x][c];
+                at_ceiling += (white[x][c] + dark_flat[x][c] >= 65500) ? 1 : 0;
+            }
+            DBG(DBG_info, "GL128 shading white ch%d min=%u mean=%.0f max=%u at_adc_ceiling=%u/%u\n",
+                c, lo, sum / std::max(1u, w.pixels), hi, at_ceiling, w.pixels);
+        }
+    }
+    auto measured = gl128_pack_shading_table(dark_flat, gains, declared);
+    dev->interface->write_ahb(GL128_AHB_SHADING, measured.size(), measured.data());
+    dev->interface->write_register(REG_0x02, 0x00);
+    // Image offsets: the shading offsets plus the device's image offset delta.
+    std::array<int, 3> image_offs;
+    for (int c = 0; c < 3; c++) {
+        image_offs[c] = std::min(255, level_offs[c] + t.image_offset_delta[c]);
+    }
+    apply_fe(image_offs, white_gains);
+
+    // Depth registers back to 8-bit before the feeds (SilverFast writes 0x33
+    // twice, 0x17 then 0x1f).
+    dev->interface->write_register(REG_DEPTH_A, 0x17);
+    dev->interface->write_register(REG_DEPTH_A, 0x1f);
+}
+
+void gl128_position_for_image(Genesys_Device* dev, const Genesys_Sensor& sensor,
+                              const ScanSession& session, unsigned feed2_steps)
+{
+    const auto& t = gl128_device_tables(dev);
+    DBG(DBG_info, "GL128: positioning feed pair %u then %u steps\n",
+        t.feed1_steps, feed2_steps);
+
+    // Lamp on before moving (0x03=0x30, as in SilverFast's image registers);
+    // gl128_lamp_on() also sets it in dev->reg so the image register write
+    // keeps it. The feeds give the lamp about 3 s to settle.
+    gl128_lamp_on(dev);
+
+    // Sensor registers before any motor move: they include the system/motor
+    // clock (0x0b=0x4c) and the motor watchdog (0x1e). SilverFast writes them
+    // once, before calibration and the feeds. Feeds at the power-on clock
+    // followed by a park at 0x4c stopped short of home.
+    for (const auto& r : sensor.custom_regs) {
+        if (gl128_is_per_pass_reg(r.address)) {
+            continue;
+        }
+        dev->interface->write_register(r.address, static_cast<std::uint8_t>(r.value));
+        dev->reg.init_reg(r.address, static_cast<std::uint8_t>(r.value));
+    }
+
+    // 0x01=0x22, 0x02=0x78, then the feeds. MOTORENB may still be set (status
+    // 0x4d after a power cycle); SilverFast feeds without clearing it. The
+    // feeds start where the white strip left the carriage, not at home.
+    dev->interface->write_register(REG_0x01, 0x22);
+    dev->interface->write_register(REG_0x02, 0x78);
+
+    // Feed 1, in the capture's order. The sensor window (STRPIXEL, ENDPIXEL,
+    // DPISET, clocks 0xa5/0xab) is the image scan's, as SilverFast writes it
+    // at 600 and 7200 dpi; the motor registers are the same in both captures.
+    const unsigned dpiset = sensor.register_dpiset;
+    const auto clock = static_cast<std::uint8_t>(gl128_pixel_clock(sensor));
+    const auto b = [](unsigned v, unsigned shift) {
+        return static_cast<std::uint8_t>((v >> shift) & 0xff);
+    };
+    const auto f1 = [&t](std::uint16_t a) {
+        return static_cast<std::uint8_t>(t.feed1_regs.get_value(a));
+    };
+    const auto f2 = [&t](std::uint16_t a) {
+        return static_cast<std::uint8_t>(t.feed2_regs.get_value(a));
+    };
+    const std::pair<std::uint16_t, std::uint8_t> FEED1_REGS[] = {
+        { 0x3b, f1(0x3b) }, { 0x01, 0x22 }, { 0x04, f1(0x04) }, { 0x05, f1(0x05) },
+        { 0x3d, b(t.feed1_steps, 16) }, { 0x3e, b(t.feed1_steps, 8) },
+        { 0x3f, b(t.feed1_steps, 0) },
+        { 0xa6, f1(0xa6) }, { 0xa7, f1(0xa7) }, { 0xa8, f1(0xa8) }, { 0xa9, f1(0xa9) },
+        { 0x7d, b(t.exposure, 16) }, { 0x7e, b(t.exposure, 8) }, { 0x7f, b(t.exposure, 0) },
+        { 0x80, f1(0x80) }, { 0x81, f1(0x81) },
+        { 0x82, b(session.pixel_startx, 16) }, { 0x83, b(session.pixel_startx, 8) },
+        { 0x84, b(session.pixel_startx, 0) },
+        { 0x85, b(session.pixel_endx, 16) }, { 0x86, b(session.pixel_endx, 8) },
+        { 0x87, b(session.pixel_endx, 0) },
+        { 0x2c, b(dpiset, 8) }, { 0x2d, b(dpiset, 0) }, { 0x1d, f1(0x1d) }, { 0x1c, f1(0x1c) },
+        { 0xa4, f1(0xa4) }, { 0xa5, clock },
+        { 0xaa, f1(0xaa) }, { 0xab, clock },
+        { 0x02, 0x18 }, { 0xae, f1(0xae) }, { 0xaf, f1(0xaf) },
+    };
+    for (const auto& r : FEED1_REGS) {
+        dev->interface->write_register(r.first, r.second);
+    }
+    gl128_upload_slope(dev, gl128_slow_motor_profile(dev));
+    dev->interface->write_register(REG_START, START_GO);
+    gl128_wait_feed_done(dev, t.feed1_steps, 30.0);
+    // Between the feeds: 0x02=0x08, FEEDL 1.
+    dev->interface->write_register(REG_0x02, 0x08);
+    gl128_write_feedl(dev, 1);
+
+    // Feed 2: FEEDL from the crop's tl_y, see gl128_feed2_steps().
+    const std::pair<std::uint16_t, std::uint8_t> FEED2_REGS[] = {
+        { 0x02, 0x18 },
+        { 0x3d, static_cast<std::uint8_t>((feed2_steps >> 16) & 0xff) },
+        { 0x3e, static_cast<std::uint8_t>((feed2_steps >> 8) & 0xff) },
+        { 0x3f, static_cast<std::uint8_t>(feed2_steps & 0xff) },
+        { 0x02, 0x18 },
+        { 0x7d, b(t.exposure, 16) }, { 0x7e, b(t.exposure, 8) }, { 0x7f, b(t.exposure, 0) },
+        { 0x1c, f2(0x1c) },
+        { 0x8a, f2(0x8a) }, { 0x8b, f2(0x8b) }, { 0x8c, f2(0x8c) }, { 0x8d, f2(0x8d) },
+        { 0x8e, f2(0x8e) }, { 0x8f, f2(0x8f) }, { 0x90, f2(0x90) }, { 0x91, f2(0x91) },
+        { 0x92, f2(0x92) },
+        { 0xae, f2(0xae) }, { 0xaf, f2(0xaf) },
+    };
+    for (const auto& r : FEED2_REGS) {
+        dev->interface->write_register(r.first, r.second);
+    }
+    gl128_upload_slope(dev, gl128_fast_motor_profile(dev));
+    dev->interface->write_register(REG_START, START_GO);
+    gl128_wait_feed_done(dev, feed2_steps, 30.0);
+
+    Status end = gl128_read_status_reliable(dev);
+    DBG(DBG_info, "GL128: positioned (at_home=%d motor=%d)\n",
+        end.is_at_home ? 1 : 0, end.is_motor_enabled ? 1 : 0);
+}
+
+} // namespace
+
+// --- CommandSet ----------------------------------------------------------------
+
+bool CommandSetGl128::needs_home_before_init_regs_for_scan(Genesys_Device* dev) const
+{
+    (void) dev;
+    // Every scan starts from home: the positioning feeds are measured from it.
+    return true;
+}
+
+void CommandSetGl128::wait_for_motor_stop(Genesys_Device* dev) const
+{
+    (void) dev;
+    // No-op: GL124 polls MOTMFLG in 0x100, which GL128 does not have (its
+    // status is 0x101). Scans end with gl128_stop_motor(), which waits for
+    // the park itself.
+}
+
+void CommandSetGl128::move_back_home(Genesys_Device* dev, bool wait_until_home) const
+{
+    (void) wait_until_home;
+    // No standalone home seek: one drove the carriage into the home stop.
+    // The carriage parks with AGOHOME at the end of every image pass.
+    // genesys calls this before every scan, so succeed when already home.
+    if (is_head_home(*dev, ScanHeadId::PRIMARY)) {
+        return;
+    }
+
+    throw SaneException("GL128 has no capture-proven standalone home seek; "
+                        "the carriage isn't at home and moving it there needs "
+                        "confirmed real-hardware behavior we don't have yet");
+}
+
+void CommandSetGl128::init(Genesys_Device* dev) const
+{
+    DBG_HELPER(dbg);
+    // As GL124. Cold/warm detection reads PWRBIT in 0x06, which is not
+    // documented for GL128; treating a warm start as cold only repeats the
+    // boot sequence.
+    sanei_genesys_asic_init(dev);
+}
+
+// Power-on initialisation: the two boot blobs, then the boot, memory layout
+// and GPO registers (pyopticfilm INIT_REGS, MEMORY_LAYOUT_REGS, GPO_REGS), in
+// SilverFast's order. Lamp (0x03) and IR (0x37) are armed separately below.
+// No cold-reset sequence: none is known for GL128.
+void CommandSetGl128::asic_boot(Genesys_Device* dev, bool cold) const
+{
+    DBG_HELPER(dbg);
+    (void) cold;
+
+    static constexpr struct { std::uint16_t addr; std::uint8_t value; } BOOT_REGS[] = {
+    // INIT_REGS
+    { 0x01, 0x22 },
+    { 0x02, 0x78 },
+    { 0x03, 0x20 },
+    { 0x04, 0x02 },
+    { 0x05, 0x48 },
+    { 0x06, 0x18 },
+    { 0x07, 0x00 },
+    { 0x08, 0x00 },
+    { 0x09, 0x00 },
+    { 0x0a, 0x40 },
+    { 0x0b, 0x6c },
+    { 0x0c, 0x00 },
+    { 0x0d, 0x00 },
+    { 0x11, 0x00 },
+    { 0x12, 0x04 },
+    { 0x13, 0x08 },
+    { 0x14, 0x01 },
+    { 0x15, 0x80 },
+    { 0x16, 0x27 },
+    { 0x17, 0x0c },
+    { 0x18, 0x10 },
+    { 0x19, 0x02 },
+    { 0x1a, 0x00 },
+    { 0x1b, 0x00 },
+    { 0x1c, 0x00 },
+    { 0x1d, 0x00 },
+    { 0x1e, 0x10 },
+    { 0x1f, 0x00 },
+    { 0x20, 0x0c },
+    { 0x21, 0x00 },
+    { 0x22, 0x1a },
+    { 0x23, 0x00 },
+    { 0x24, 0x1a },
+    { 0x25, 0x00 },
+    { 0x26, 0x00 },
+    { 0x27, 0x00 },
+    { 0x2b, 0x20 },
+    { 0x2c, 0x12 },
+    { 0x2d, 0xc0 },
+    { 0x30, 0x6f },
+    { 0x31, 0x00 },
+    { 0x32, 0x22 },
+    { 0x33, 0x04 },
+    { 0x34, 0x80 },
+    { 0x35, 0x2f },
+    { 0x36, 0x1c },
+    { 0x37, 0xc0 },
+    { 0x38, 0x44 },
+    { 0x39, 0x00 },
+    { 0x3a, 0x00 },
+    { 0x3b, 0xff },
+    { 0x3c, 0xff },
+    { 0x3d, 0x00 },
+    { 0x3e, 0x00 },
+    { 0x3f, 0x01 },
+    { 0x4f, 0x03 },
+    { 0x52, 0x07 },
+    { 0x53, 0x09 },
+    { 0x54, 0x0b },
+    { 0x55, 0x01 },
+    { 0x56, 0x03 },
+    { 0x57, 0x05 },
+    { 0x5a, 0x12 },
+    { 0x5b, 0x00 },
+    { 0x5c, 0x40 },
+    { 0x5e, 0x1f },
+    { 0x5f, 0x05 },
+    { 0x60, 0x00 },
+    { 0x61, 0x00 },
+    { 0x63, 0x20 },
+    { 0x67, 0x7f },
+    { 0x68, 0x7f },
+    { 0x69, 0x01 },
+    { 0x70, 0x01 },
+    { 0x71, 0x02 },
+    { 0x72, 0x03 },
+    { 0x73, 0x04 },
+    { 0x74, 0x00 },
+    { 0x75, 0x00 },
+    { 0x76, 0x00 },
+    { 0x77, 0x00 },
+    { 0x78, 0x00 },
+    { 0x79, 0x0f },
+    { 0x7a, 0xff },
+    { 0x7b, 0xff },
+    { 0x7c, 0xff },
+    { 0x7d, 0x00 },
+    { 0x7e, 0x2a },
+    { 0x7f, 0xf8 },
+    { 0x80, 0x00 },
+    { 0x81, 0x22 },
+    { 0x82, 0x00 },
+    { 0x83, 0x01 },
+    { 0x84, 0x18 },
+    { 0x85, 0x00 },
+    { 0x86, 0x00 },
+    { 0x87, 0x00 },
+    { 0x93, 0x00 },
+    { 0x94, 0x00 },
+    { 0x95, 0x00 },
+    { 0x9d, 0x08 },
+    { 0xa0, 0x00 }, // step types, from the motor profiles (see below)
+    { 0xa4, 0x00 },
+    { 0xa5, 0x20 },
+    { 0xa6, 0x00 },
+    { 0xa7, 0x00 },
+    { 0xa8, 0x00 },
+    { 0xa9, 0x00 },
+    { 0xaa, 0x00 },
+    { 0xab, 0x30 },
+    { 0xb8, 0x00 },
+    { 0xb9, 0x38 },
+    { 0xba, 0x00 },
+    { 0xbd, 0x00 },
+    { 0xbe, 0x00 },
+    { 0xbf, 0x00 },
+    // MEMORY_LAYOUT_REGS
+    { 0xd0, 0x0a },
+    { 0xd1, 0x0a },
+    { 0xd2, 0x0a },
+    { 0xe0, 0x00 },
+    { 0xe1, 0x68 },
+    { 0xe2, 0x0b },
+    { 0xe3, 0x00 },
+    { 0xe4, 0x0b },
+    { 0xe5, 0x01 },
+    { 0xe6, 0x15 },
+    { 0xe7, 0x99 },
+    { 0xe8, 0x15 },
+    { 0xe9, 0x9a },
+    { 0xea, 0x20 },
+    { 0xeb, 0x32 },
+    { 0xec, 0x20 },
+    { 0xed, 0x33 },
+    { 0xee, 0x2a },
+    { 0xef, 0xcb },
+    { 0xf0, 0x2a },
+    { 0xf1, 0xcc },
+    { 0xf2, 0x35 },
+    { 0xf3, 0x64 },
+    { 0xf4, 0x35 },
+    { 0xf5, 0x65 },
+    { 0xf6, 0x3f },
+    { 0xf7, 0xfd },
+    { 0xf8, 0x05 },
+    // GPO_REGS
+    { 0xa2, 0x00 },
+    { 0xa3, 0x00 },
+    { 0xa4, 0x00 },
+    { 0xa6, 0x00 },
+    { 0xa7, 0x00 },
+    { 0xa8, 0x00 },
+    { 0xa9, 0x00 },
+    { 0xaa, 0x00 },
+    { 0xac, 0x00 },
+    { 0xad, 0x01 },
+    { 0xae, 0x00 },
+    };
+
+    // Order and gaps as in SilverFast's USB captures (the same in all four).
+    // 0xa0: fast-move step type in bits 5-3 and scan step type in bits 2-0,
+    // as on GL124, from the motor's fast and scan profiles (the captures
+    // write 0x12: quarter steps for both).
+    const auto step_select = static_cast<std::uint8_t>(
+            (static_cast<unsigned>(gl128_fast_motor_profile(dev).step_type) << 3) |
+            static_cast<unsigned>(gl128_slow_motor_profile(dev).step_type));
+    for (const auto& r : BOOT_REGS) {
+        const std::uint8_t value = r.addr == 0xa0 ? step_select : r.value;
+        dev->interface->write_register(r.addr, value);
+        // Shared code (e.g. regs_set_optical_off()) looks registers up in
+        // dev->reg, so every boot register must exist there.
+        dev->reg.init_reg(r.addr, value);
+    }
+
+    // 0x01 is set per scan, but shared code may read it from dev->reg before
+    // the first one; 0x22 is its boot value.
+    dev->reg.init_reg(REG_0x01, 0x22);
+
+    // Clock set-up, then start-up registers. SilverFast writes 0x10=0x0c and
+    // 0x13=0x0c with the 0x8c request (VALUE_BUF_ENDACCESS, as genesys does
+    // for the GL845 OpticFilm 8200i in gl846.cpp), then ASIC registers
+    // 0x0b=0x44, 0x13=0x0f, 0x0b=0x4c (SilverFast's capture from power-on, and
+    // every later boot). Without the clock set-up every level is ~1.25x
+    // SilverFast's (dark too) and the white strip clips; the setting persists
+    // until power-off.
+    dev->interface->write_0x8c(0x10, 0x0c);
+    dev->interface->write_0x8c(0x13, 0x0c);
+    static constexpr std::pair<std::uint16_t, std::uint8_t> STARTUP_REGS[] = {
+        { 0x0b, 0x44 }, { 0x13, 0x0f }, { 0x0b, 0x4c },
+    };
+    for (const auto& r : STARTUP_REGS) {
+        dev->interface->write_register(r.first, r.second);
+        dev->reg.init_reg(r.first, r.second);
+    }
+
+    // First lamp pulse train: 0x03 = 0x10, 0x00; the AFE boot values, the two
+    // boot blobs (boot does not work without them) and 0x33 = 0x07, 0x07,
+    // 0x17, 0x1f; then, 55 ms after 0x00, 0x03 = 0x20, 0x30, 0x20, 0x30.
+    // Without the train 0x03=0x20 does not switch the lamp off after a power
+    // cycle, and the dark reference is lit.
+    gl128_write_lamp_pulses(dev, { 0x10, 0x00 });
+    const auto lamp_off_at = std::chrono::steady_clock::now();
+    for (std::uint16_t addr = 0x00; addr <= 0x07; addr++) {
+        dev->interface->write_fe_register(static_cast<std::uint8_t>(addr),
+                                          dev->frontend_initial.regs.get_value(addr));
+    }
+    {
+        std::vector<std::uint8_t> blob_a(34, 0);
+        std::vector<std::uint8_t> blob_b(34, 0);
+        blob_b[32] = 0x33;
+        dev->interface->write_ahb(0x000FFF00, blob_a.size(), blob_a.data());
+        dev->interface->write_ahb(0x000FFF01, blob_b.size(), blob_b.data());
+    }
+    dev->interface->write_register(REG_DEPTH_A, 0x07);
+    dev->interface->write_register(REG_DEPTH_A, 0x07);
+    std::this_thread::sleep_for(std::chrono::milliseconds(23));
+    dev->interface->write_register(REG_DEPTH_A, 0x17);
+    dev->interface->write_register(REG_DEPTH_A, 0x1f);
+    std::this_thread::sleep_until(lamp_off_at + std::chrono::milliseconds(55));
+    gl128_write_lamp_pulses(dev, { 0x20, 0x30, 0x20, 0x30 });
+
+    // 65 ms later the clock set-up again (0x8c requests), then the
+    // register pass sets ASIC register 0x13 back to 0x08 (the boot value).
+    std::this_thread::sleep_for(std::chrono::milliseconds(65));
+    dev->interface->write_0x8c(0x10, 0x0c);
+    dev->interface->write_0x8c(0x13, 0x0c);
+    dev->interface->write_register(0x13, 0x08);
+    dev->reg.init_reg(0x13, 0x08);
+    dev->lamp_boot_sequence_pending = true;
+    dev->lamp_warmup_pending = cold; // asic_boot() also runs on warm opens
+}
+
+void CommandSetGl128::init_regs_for_warmup(Genesys_Device* dev, const Genesys_Sensor& sensor,
+                                           Genesys_Register_Set* regs) const
+{
+    (void) dev; (void) sensor; (void) regs;
+    // Not used: the lamp warms up inside gl128_run_asic_shading().
+    throw SaneException("GL128 init_regs_for_warmup() not yet implemented");
+}
+
+void CommandSetGl128::init_regs_for_shading(Genesys_Device* dev, const Genesys_Sensor& sensor,
+                                            Genesys_Register_Set& regs) const
+{
+    DBG_HELPER(dbg);
+
+    // Called for both the dark and the white pass; genesys switches lamp and
+    // motor after this returns.
+    constexpr unsigned SHADING_LINES = 128;
+
+    // Recompute the session from dev->settings: scanner_move() overwrites
+    // dev->session with its own (empty-window) session before this runs.
+    ScanSession real_session = dev->cmd_set->calculate_scan_session(dev, sensor, dev->settings);
+
+    // DEPTH8 registers deliver LINCNT/2 rows, so LINCNT = 2 * 128 gives 128
+    // rows; genesys reads channels*2*pixels*(params.lines + 1) bytes, so
+    // params.lines = 127.
+    gl128_setup_shading_strip_regs(gl128_device_tables(dev), sensor, real_session,
+                                   2 * SHADING_LINES, regs);
+
+    // The reference passes need the image's per-channel exposure tables, as
+    // SilverFast uploads them before its shading passes.
+    gl128_upload_image_tables(dev, gl128_asic_dpi(sensor));
+
+    // genesys_shading_calibration_impl() sizes its read from
+    // dev->calib_session: channels * 2 * params.pixels * (params.lines + 1).
+    // Width: (ENDPIXEL - STRPIXEL) / (7200 / asic_dpi).
+    const unsigned span = real_session.pixel_endx - real_session.pixel_startx;
+    const unsigned factor = std::max(1u, sensor.full_resolution / gl128_asic_dpi(sensor));
+    const unsigned acquire_width = std::max(1u, span / factor);
+
+    ScanSession calib;
+    calib.params.xres = real_session.params.xres;
+    calib.params.yres = real_session.params.xres;
+    calib.params.startx = 0;
+    calib.params.starty = 0;
+    calib.params.pixels = acquire_width;
+    calib.params.lines = SHADING_LINES - 1;
+    calib.params.depth = 16;
+    calib.params.channels = 3;
+    calib.params.scan_method = dev->settings.scan_method;
+    calib.params.scan_mode = ScanColorMode::COLOR_SINGLE_PASS;
+    calib.params.color_filter = ColorFilter::RED;
+    calib.params.flags = ScanFlag::DISABLE_SHADING | ScanFlag::DISABLE_GAMMA |
+                         ScanFlag::DISABLE_BUFFER_FULL_MOVE;
+    calib.full_resolution = sensor.full_resolution;
+    calib.optical_resolution = sensor.full_resolution;
+    calib.output_resolution = real_session.params.xres;
+    calib.output_pixels = acquire_width;
+    calib.optical_pixels = acquire_width;
+    calib.pixel_startx = real_session.pixel_startx;
+    calib.pixel_endx = real_session.pixel_endx;
+    calib.output_line_count = SHADING_LINES;
+    calib.optical_line_count = SHADING_LINES;
+    calib.output_channel_bytes = acquire_width * 2;
+    calib.output_line_bytes = calib.output_channel_bytes * 3;
+    calib.output_line_bytes_raw = calib.output_line_bytes;
+    calib.output_total_bytes_raw = calib.output_line_bytes * SHADING_LINES;
+    calib.output_total_bytes = calib.output_total_bytes_raw;
+    // As in calculate_scan_session().
+    calib.buffer_size_read = align_multiple_ceil(calib.output_line_bytes_raw * 64, 2);
+    calib.use_host_side_calib = sensor.use_host_side_calib;
+    calib.computed = true;
+
+    dev->calib_session = calib;
+}
+
+void CommandSetGl128::init_regs_for_scan_session(Genesys_Device* dev, const Genesys_Sensor& sensor,
+                                                 Genesys_Register_Set* reg,
+                                                 const ScanSession& session) const
+{
+    // Image pass only (scanner_move() feeds carry ScanFlag::FEEDING): ASIC
+    // shading and the positioning feeds run here, before the image registers
+    // are built, since they change dev->reg.
+    if ((session.params.flags & ScanFlag::FEEDING) == ScanFlag::NONE) {
+        // Travel limit, checked before any motion: the image pass (LINCNT *
+        // steps_per_inch / (4 * asic_dpi) steps) must end no further than the device
+        // tables' max_image_end_steps (SilverFast's own full-frame passes on
+        // the 8200i SE: about 25 mm from the top of the window).
+        const unsigned feed2 = gl128_feed2_steps(dev);
+        {
+            const unsigned asic_dpi_gate = gl128_asic_dpi(sensor);
+            const long travel = static_cast<long>(gl128_device_tables(dev).max_image_end_steps) -
+                                static_cast<long>(feed2);
+            const unsigned max_lincnt = travel <= 0 ? 0u :
+                    std::max(4u, (static_cast<unsigned>(travel) * asic_dpi_gate * 4u /
+                                  gl128_device_tables(dev).steps_per_inch) / 4u * 4u);
+            const unsigned want_lincnt = session.params.lines * 4u;
+            if (want_lincnt > max_lincnt) {
+                throw SaneException(SANE_STATUS_INVAL,
+                        "GL128: scan height too large -- %u lines at %u dpi would run "
+                        "past the scan-window end (max %u lines). Reduce the height.",
+                        session.params.lines / gl128_host_downsample(sensor, session.params.yres),
+                        session.params.yres,
+                        max_lincnt / 4u / gl128_host_downsample(sensor, session.params.yres));
+            }
+        }
+        {
+            Gl128ShadingWindow w{};
+            w.strpixel = session.pixel_startx;
+            w.endpixel = session.pixel_endx;
+            w.asic_dpi = gl128_asic_dpi(sensor);
+            w.dpiset = sensor.register_dpiset;
+            w.pixels = std::max(1u, (session.pixel_endx - session.pixel_startx) /
+                                    std::max(1u, sensor.full_resolution / w.asic_dpi));
+            w.timing = gl128_timing(gl128_device_tables(dev), sensor,
+                                    session.pixel_endx - session.pixel_startx);
+            // The front end must be programmed before the references are
+            // measured (as GL124's scan setup does); with the power-on AFE
+            // the dark reference reads 33-44k.
+            set_fe(dev, sensor, AFE_SET);
+            gl128_run_asic_shading(dev, sensor, w);
+        }
+        gl128_position_for_image(dev, sensor, session, feed2);
+        DBG(DBG_info, "GL128: image %ux%u dpi, %u lines, unstagger %u buffer rows\n",
+            session.params.xres, session.params.yres, session.params.lines,
+            session.num_staggered_lines);
+    }
+
+    // Sensor timing and AFE sampling registers (sensor.custom_regs), as
+    // gl124_setup_sensor() applies them. Without them the CCD is not clocked.
+    for (const auto& r : sensor.custom_regs) {
+        reg->init_reg(r.address, static_cast<std::uint8_t>(r.value));
+    }
+
+    DBG_HELPER(dbg);
+    session.assert_computed();
+
+    // Register values for the pass; begin_scan() starts it.
+
+    const unsigned asic_dpi = gl128_asic_dpi(sensor);
+
+    // 0x01: SHDAREA on, SCAN (set by begin_scan()) and STAGGER off. DVDSET on
+    // for the image pass, so the ASIC applies the shading table from
+    // gl128_run_asic_shading() (SilverFast's image 0x01 is 0x23); off for
+    // feeds.
+    std::uint8_t reg01 = 0x22; // boot value
+    reg01 = (reg01 | REG_0x01_SHDAREA) & ~REG_0x01_SCAN & ~REG_0x01_STAGGER;
+    if ((session.params.flags & ScanFlag::FEEDING) == ScanFlag::NONE) {
+        reg01 |= REG_0x01_DVDSET;
+    } else {
+        reg01 &= ~REG_0x01_DVDSET;
+    }
+    reg->init_reg(REG_0x01, reg01);
+
+    // 0x02: MTRPWR|AGOHOME for the image pass (0x30 in the captures), so the
+    // carriage parks at the end. scanner_move() feeds (ScanFlag::FEEDING)
+    // with a real distance use MTRPWR|FASTFED (0x18, as SilverFast's feeds).
+    // A zero-distance feed (scanner_move_to_ta() on this TA-only scanner)
+    // keeps MTRPWR|AGOHOME with FEEDL 1: FASTFED with FEEDL 0 never reported
+    // the motor stopped.
+    const bool is_feeding = (session.params.flags & ScanFlag::FEEDING) != ScanFlag::NONE;
+    const bool is_real_feed = is_feeding && session.params.starty > 0;
+    reg->init_reg(REG_0x02, is_real_feed
+                       ? static_cast<std::uint8_t>(REG_0x02_MTRPWR | REG_0x02_FASTFED)
+                       : static_cast<std::uint8_t>(REG_0x02_MTRPWR | REG_0x02_AGOHOME));
+
+    // REG_0x03 / REG_IR: not written here. For the image path the lamp is
+    // switched on (0x03=0x30, capture value) by gl128_position_for_image()
+    // above, which mirrors it into dev->reg before these values are built.
+
+    // Depth registers 0x33=0x1f, 0xaf=0xff: 16-bit LE samples.
+    reg->init_reg(REG_DEPTH_A, DEPTH8_A);
+    reg->init_reg(REG_DEPTH_B, DEPTH8_B);
+
+    // LINCNT counts half buffer rows (see calculate_scan_session()).
+    const unsigned register_lincnt = session.optical_line_count * 2;
+    gl128_init_reg24(reg, REG_LINCNT, register_lincnt);
+
+    // LPERIOD and the image-pass clocks: gl128_timing() (sensor entry;
+    // width-dependent at 7200 dpi from the SilverFast captures).
+    const Gl128Timing timing = gl128_timing(gl128_device_tables(dev), sensor,
+                                            session.pixel_endx - session.pixel_startx);
+    gl128_init_reg24(reg, REG_LPERIOD, timing.lperiod);
+
+    gl128_init_reg16(reg, REG_DPISET, static_cast<std::uint16_t>(sensor.register_dpiset));
+
+    gl128_init_reg24(reg, REG_STRPIXEL, session.pixel_startx);
+    gl128_init_reg24(reg, REG_ENDPIXEL, session.pixel_endx);
+
+    // EXPOSURE is the same at every resolution in the captures.
+    gl128_init_reg24(reg, REG_EXPOSURE, gl128_device_tables(dev).exposure);
+
+    // FEEDL: 1 for the image pass (as in the captures) and for zero-distance
+    // feeds (see 0x02 above); the requested steps for a real feed.
+    gl128_init_reg24(reg, REG_FEEDL, is_real_feed ? session.params.starty : 1);
+
+    // Image-pass dummy and pixel clocks.
+    reg->init_reg(0x2B, static_cast<std::uint8_t>(timing.image.dummy));
+    reg->init_reg(0xA5, static_cast<std::uint8_t>(timing.image.clk_a));
+    reg->init_reg(0xAB, static_cast<std::uint8_t>(timing.image.clk_b));
+
+    // Motor registers are not taken from dev->motor.profiles (unlike GL124):
+    // the image pass uses the slope tables uploaded from the capture.
+
+    dev->read_active = true;
+    dev->session = session;
+    dev->total_bytes_read = 0;
+    dev->total_bytes_to_read = static_cast<std::size_t>(session.output_line_bytes_requested) *
+                               static_cast<std::size_t>(session.params.lines);
+
+    // As gl124: set up the image pipeline that sane_read() pulls from.
+    dev->line_count = 0;
+    setup_image_pipeline(*dev, session);
+
+    // The frontend reads what the pipeline outputs (also what
+    // sane_get_parameters() reports). The travel limit leaves no room to scan
+    // extra lines for the colour line shift, so the image is a few rows
+    // shorter than params.lines.
+    dev->total_bytes_to_read = dev->pipeline.get_output_row_bytes() *
+                               dev->pipeline.get_output_height();
+
+    // Image pass: channel exposure tables before the register writes and
+    // START, in the capture's order.
+    if (!is_feeding) {
+        gl128_upload_image_tables(dev, asic_dpi);
+    }
+}
+
+void CommandSetGl128::set_fe(Genesys_Device* dev, const Genesys_Sensor& sensor,
+                             std::uint8_t set) const
+{
+    DBG_HELPER(dbg);
+    (void) sensor;
+
+    if (set == AFE_INIT) {
+        dev->frontend = dev->frontend_initial;
+    }
+
+    // AFE registers 0x00-0x07 through the 0x51 (index) / 0x5d, 0x5e (data)
+    // bridge, which write_fe_register() uses for GL124 and GL128. GL124's TI
+    // AFE start sequence does not apply to this Analog Devices style AFE.
+    for (std::uint16_t addr = 0x00; addr <= 0x07; addr++) {
+        dev->interface->write_fe_register(static_cast<std::uint8_t>(addr),
+                                          dev->frontend.regs.get_value(addr));
+    }
+}
+
+void CommandSetGl128::set_powersaving(Genesys_Device* dev, int delay) const
+{
+    DBG_HELPER_ARGS(dbg, "delay = %d", delay);
+    (void) dev;
+    // No-op. GL124 puts the delay in the upper nibble of 0x03, which holds
+    // the lamp and XPA bits on GL128; no power-saving mechanism is known.
+}
+
+void CommandSetGl128::save_power(Genesys_Device* dev, bool enable) const
+{
+    DBG_HELPER_ARGS(dbg, "enable = %d", enable);
+    (void) dev;
+    // No-op, as GL124.
+}
+
+void CommandSetGl128::begin_scan(Genesys_Device* dev, const Genesys_Sensor& sensor,
+                                 Genesys_Register_Set* regs, bool start_motor) const
+{
+    DBG_HELPER(dbg);
+    (void) sensor; (void) start_motor;
+
+    // genesys' host-side shading passes set MTRPWR. A register set without
+    // AGOHOME or FASTFED is such a pass; run it stationary, since nothing
+    // would bring the carriage back home afterwards.
+    if (regs != nullptr && regs->has_reg(REG_0x02)) {
+        std::uint8_t r02 = regs->get8(REG_0x02);
+        if ((r02 & (REG_0x02_AGOHOME | REG_0x02_FASTFED)) == 0 && (r02 & REG_0x02_MTRPWR)) {
+            r02 = static_cast<std::uint8_t>(r02 & ~REG_0x02_MTRPWR);
+            regs->find_reg(REG_0x02).value = r02;
+            dev->interface->write_register(REG_0x02, r02);
+        }
+    }
+
+    // Capture order: 0x0d=0x07, 0x01 |= SCAN, 0x0f=0x01. Stationary passes
+    // are started the same way (the motor state comes from 0x02).
+
+    dev->interface->write_register(REG_CLRCNT, CLRCNT_ALL);
+    std::uint8_t reg01 = static_cast<std::uint8_t>(dev->reg.get8(REG_0x01) | REG_0x01_SCAN);
+    if (regs != nullptr && regs->has_reg(REG_0x01)) {
+        reg01 = static_cast<std::uint8_t>(regs->get8(REG_0x01) | REG_0x01_SCAN);
+        regs->find_reg(REG_0x01).value = reg01;
+    }
+    dev->interface->write_register(REG_0x01, reg01);
+    dev->reg.init_reg(REG_0x01, reg01);
+    dev->interface->write_register(REG_START, START_GO);
+}
+
+void CommandSetGl128::end_scan(Genesys_Device* dev, Genesys_Register_Set* regs,
+                               bool check_stop) const
+{
+    DBG_HELPER(dbg);
+    (void) regs; (void) check_stop;
+    gl128_stop_motor(dev);
+}
+
+void CommandSetGl128::send_gamma_table(Genesys_Device* dev, const Genesys_Sensor& sensor) const
+{
+    DBG_HELPER(dbg);
+    (void) dev; (void) sensor;
+    // No-op: output is linear. The shared gamma upload writes AHB
+    // 0x01000000, which SilverFast never writes.
+}
+
+// offset_calibration() / coarse_gain_calibration(): not used. The model sets
+// ModelFlag::DISABLE_ADC_CALIBRATION; gl128_run_asic_shading() programs the
+// front end with SilverFast's fixed codes before every image pass.
+void CommandSetGl128::offset_calibration(Genesys_Device* dev, const Genesys_Sensor& sensor,
+                                         Genesys_Register_Set& regs) const
+{
+    (void) dev; (void) sensor; (void) regs;
+}
+
+void CommandSetGl128::coarse_gain_calibration(Genesys_Device* dev, const Genesys_Sensor& sensor,
+                                              Genesys_Register_Set& regs, int dpi) const
+{
+    (void) dev; (void) sensor; (void) regs; (void) dpi;
+}
+
+SensorExposure CommandSetGl128::led_calibration(Genesys_Device* dev, const Genesys_Sensor& sensor,
+                                                Genesys_Register_Set& regs) const
+{
+    (void) dev; (void) sensor; (void) regs;
+    // Not used: exposure is fixed (device tables) and the lamp is not an LED
+    // array.
+    throw SaneException("GL128 led_calibration() not yet implemented");
+}
+
+void CommandSetGl128::update_hardware_sensors(struct Genesys_Scanner* s) const
+{
+    DBG_HELPER(dbg);
+    (void) s;
+    // No-op: button polling is not known for this scanner.
+}
+
+void CommandSetGl128::update_home_sensor_gpio(Genesys_Device& dev) const
+{
+    DBG_HELPER(dbg);
+    (void) dev;
+    // No-op: the captures show no GPIO access around scan start.
+}
+
+void CommandSetGl128::load_document(Genesys_Device* dev) const
+{
+    (void) dev;
+    // Not a sheetfed scanner.
+    throw SaneException("not implemented");
+}
+
+void CommandSetGl128::detect_document_end(Genesys_Device* dev) const
+{
+    (void) dev;
+    throw SaneException("not implemented");
+}
+
+void CommandSetGl128::eject_document(Genesys_Device* dev) const
+{
+    (void) dev;
+    throw SaneException("not implemented");
+}
+
+void CommandSetGl128::send_shading_data(Genesys_Device* dev, const Genesys_Sensor& sensor,
+                                        std::uint8_t* data, int size) const
+{
+    (void) dev; (void) sensor; (void) data; (void) size;
+    // Not used: host-side shading is disabled; gl128_run_asic_shading()
+    // uploads the ASIC shading table itself.
+    throw SaneException("GL128 send_shading_data() not yet implemented");
+}
+
+ScanSession CommandSetGl128::calculate_scan_session(const Genesys_Device* dev,
+                                                    const Genesys_Sensor& sensor,
+                                                    const Genesys_Settings& settings) const
+{
+    // Geometry in native 7200 dpi units (pyopticfilm compute_geometry(),
+    // native-units branch).
+
+    const unsigned asic_dpi = gl128_asic_dpi(sensor);
+    const unsigned offset = static_cast<unsigned>(sensor.output_pixel_offset);
+    const unsigned optical_res = sensor.full_resolution; // 7200
+
+    // Transparency-only scanner: the TA offsets always apply.
+    // The image is mirrored in X after readout, so SANE's tl_x
+    // (measured from the displayed left edge) maps to the far end of the
+    // native scan window: native = x_size_ta - (tl_x + width).
+    const float width_mm = static_cast<float>(settings.pixels) * MM_PER_INCH /
+                           static_cast<float>(settings.xres);
+    const float mirrored_tl_x = std::max(0.0f, dev->model->x_size_ta - (settings.tl_x + width_mm));
+    const float tl_x_mm = dev->model->x_offset_ta + mirrored_tl_x;
+    const float tl_y_mm = dev->model->y_offset_ta + settings.tl_y;
+
+
+    const unsigned origin_native = offset * optical_res / asic_dpi;
+    const unsigned frame_shift = gl128_device_tables(dev).optical_end_inactive;
+    const long tlx_native = lround(tl_x_mm * optical_res / MM_PER_INCH);
+    if (tlx_native < 0) {
+        throw SaneException("GL128: requested scan area starts left of the TA origin");
+    }
+
+    // The CCD's even and odd native columns are 4/7200 in apart in Y (see the
+    // stagger_y comment below). The ASIC reads every (optical_res/asic_dpi)-th
+    // native column from STRPIXEL: an even step keeps one parity (no zipper),
+    // an odd step (7200: 1, 2400: 3, 1440: 5) alternates parity per output
+    // column. The unstagger shift is applied per pipeline column parity, so
+    // the window must start on an even native column (as genesys
+    // compute_session() aligns pixel_startx for staggered sensors) and on a
+    // multiple of the step: round down to a multiple of 2*step.
+    const unsigned column_step = std::max(1u, optical_res / asic_dpi);
+    const bool staggered = (column_step % 2) == 1;
+    unsigned pixel_startx = origin_native + frame_shift +
+                            static_cast<unsigned>(tlx_native);
+    if (staggered) {
+        pixel_startx -= pixel_startx % (2 * column_step);
+    }
+
+    // Native width from the requested pixel count. Below 600 dpi the ASIC
+    // runs at asic_dpi and the host averages host_downsample pixels.
+    const unsigned host_downsample = gl128_host_downsample(sensor, settings.xres);
+    unsigned optical_pixels = static_cast<unsigned>(
+        (static_cast<std::uint64_t>(settings.pixels) * optical_res) / settings.xres);
+    // The native span must be a multiple of lcm(4, 2 * step) so each USB
+    // line has an even pixel count; odd counts shear the image. Rounded up,
+    // and build_image_pipeline() crops the surplus off the native end (the
+    // displayed left after mirroring), so the output is exactly the
+    // requested width.
+    {
+        const unsigned factor = std::max(1u, optical_res / asic_dpi);
+        unsigned a = 4, b = 2 * factor;
+        while (b) { unsigned t = a % b; a = b; b = t; }
+        const unsigned align = 4 * (2 * factor) / a; // lcm(4, 2*factor)
+        optical_pixels = ((optical_pixels + align - 1) / align) * align;
+    }
+
+    const unsigned pixel_endx = pixel_startx + optical_pixels;
+    const unsigned output_pixels = static_cast<unsigned>(
+        (static_cast<std::uint64_t>(optical_pixels) * asic_dpi) / optical_res);
+
+    const unsigned output_startx = pixel_startx * asic_dpi / optical_res;
+    if (output_startx < offset) {
+        throw SaneException("GL128: computed startx underflows output_pixel_offset");
+    }
+    const unsigned startx = output_startx - offset;
+    const unsigned starty = static_cast<unsigned>(
+        std::max(0L, lround(tl_y_mm * dev->motor.base_ydpi / MM_PER_INCH)));
+
+    ScanSession session;
+    session.params.xres = settings.xres;
+    session.params.yres = settings.yres;
+    session.params.startx = startx;
+    session.params.starty = starty;
+    session.params.pixels = output_pixels;
+    session.params.requested_pixels = settings.requested_pixels;
+    // Lines at asic_dpi; the pipeline averages host_downsample of them per
+    // output line.
+    session.params.lines = settings.lines * host_downsample;
+    session.params.depth = settings.depth;
+    session.params.channels = settings.get_channels();
+    session.params.scan_method = settings.scan_method;
+    session.params.scan_mode = settings.scan_mode;
+    // Gray: the GL128 always delivers chunky RGB. Scan colour and keep the
+    // selected colour filter's channel on the host (as genesys does for
+    // ModelFlag::HOST_SIDE_GRAY).
+    session.use_host_side_gray = false;
+    if (session.params.channels == 1) {
+        session.use_host_side_gray = true;
+        session.params.channels = 3;
+        session.params.scan_mode = ScanColorMode::COLOR_SINGLE_PASS;
+    }
+    session.params.color_filter = settings.color_filter;
+    session.params.contrast_adjustment = dev->settings.contrast;
+    session.params.brightness_adjustment = dev->settings.brightness;
+    session.params.flags = ScanFlag::NONE;
+
+    session.full_resolution = optical_res;
+    session.optical_resolution = optical_res;
+    session.output_resolution = settings.xres;
+    session.output_pixels = output_pixels;
+    session.optical_pixels = optical_pixels;
+    session.optical_pixels_raw = optical_pixels;
+    session.pixel_startx = pixel_startx;
+    session.pixel_endx = pixel_endx;
+    session.output_startx = output_startx;
+
+    // Colour line shift 0/24/48 at 7200 dpi, scaled as compute_session()
+    // does.
+    session.color_shift_lines_r = dev->model->ld_shift_r * asic_dpi / dev->motor.base_ydpi;
+    session.color_shift_lines_g = dev->model->ld_shift_g * asic_dpi / dev->motor.base_ydpi;
+    session.color_shift_lines_b = dev->model->ld_shift_b * asic_dpi / dev->motor.base_ydpi;
+    session.max_color_shift_lines = std::max(session.color_shift_lines_r,
+                                             std::max(session.color_shift_lines_g,
+                                                      session.color_shift_lines_b));
+
+    // The ASIC's STAGGER bit (0x01) is never set; SilverFast corrects the
+    // CCD stagger on the host. Even native columns see the film 4/7200 in
+    // after odd ones (measured in SilverFast's raw 7200 dpi data: 7-8 buffer
+    // rows), the same as CCD_PLUSTEK_OPTICFILM_8200I's StaggerConfig{4, 0}.
+    // At odd column steps (7200, 2400, 1440) output columns alternate
+    // between even and odd native columns. Below 7200 the offset is not a
+    // whole number of lines, so for GL128 stagger_y counts 2x-oversampled
+    // buffer rows and build_image_pipeline() applies it before the row-pair
+    // average: round(8 * asic_dpi / 7200) rows (7200: 8, 2400: 3, 1440: 2).
+    // Measured on hardware after the correction: 0.25 lines left at 7200,
+    // 0.4 at 2400 (1.6 before). Like the colour shift, it crops lines off the
+    // bottom.
+    if (staggered) {
+        const unsigned rows = (8 * asic_dpi + optical_res / 2) / optical_res;
+        session.stagger_y = StaggerConfig{rows, 0};
+        session.num_staggered_lines = rows;
+    } else {
+        session.stagger_y = StaggerConfig{};
+        session.num_staggered_lines = 0;
+    }
+
+    // LINCNT is 4 per output line (145 lines -> 580 in the captures), with no
+    // extra lines for the colour shift.
+    constexpr unsigned LINCNT_PER_LINE = 4;
+    const unsigned register_lincnt = (session.params.lines /* + 0 extra_lines */) * LINCNT_PER_LINE;
+
+    // The scanner returns LINCNT / 2 rows of 16-bit RGB: Y is sampled twice
+    // per output line, and the pipeline averages the row pairs.
+    session.output_line_count = register_lincnt / 2;
+    session.optical_line_count = session.output_line_count; // not is_cis
+
+    session.output_channel_bytes = (output_pixels * settings.depth + 7) / 8;
+    session.output_line_bytes = session.output_channel_bytes * session.params.channels;
+    session.output_line_bytes_raw = session.output_line_bytes;
+    session.output_line_bytes_requested = session.output_line_bytes;
+    session.output_total_bytes_raw = session.output_line_bytes * session.optical_line_count;
+    session.output_total_bytes = session.output_total_bytes_raw;
+
+    // USB read buffer size, as compute_session() sets it.
+    session.buffer_size_read = align_multiple_ceil(session.output_line_bytes_raw * 64, 2);
+
+    session.use_host_side_calib = sensor.use_host_side_calib;
+    session.computed = true;
+
+    return session;
+}
+
+} // namespace gl128
+} // namespace genesys
diff --git a/backend/genesys/gl128.h b/backend/genesys/gl128.h
new file mode 100644
index 0000000..6a4d6a1
--- /dev/null
+++ b/backend/genesys/gl128.h
@@ -0,0 +1,115 @@
+/* sane - Scanner Access Now Easy.
+
+   Copyright (C) 2026 vermiculous <vermiculous@disroot.org>
+   Portions derived from pyopticfilm (https://github.com/jboneng/pyopticfilm),
+   Copyright (C) jboneng, used with permission.
+
+   This file is part of the SANE package.
+
+   This program is free software; you can redistribute it and/or
+   modify it under the terms of the GNU General Public License as
+   published by the Free Software Foundation; either version 2 of the
+   License, or (at your option) any later version.
+
+   This program is distributed in the hope that it will be useful, but
+   WITHOUT ANY WARRANTY; without even the implied warranty of
+   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
+   General Public License for more details.
+
+   You should have received a copy of the GNU General Public License
+   along with this program.  If not, see <https://www.gnu.org/licenses/>.
+*/
+
+/*
+ * GL128 CommandSet (Plustek OpticFilm 8200i SE).
+ *
+ * Inherits CommandSetCommon for is_head_home(), set_xpa_lamp_power() and
+ * set_motor_mode(), whose generic paths apply to this scanner.
+ */
+
+#ifndef BACKEND_GENESYS_GL128_H
+#define BACKEND_GENESYS_GL128_H
+
+#include "genesys.h"
+#include "command_set_common.h"
+
+namespace genesys {
+namespace gl128 {
+
+class CommandSetGl128 : public CommandSetCommon
+{
+public:
+    ~CommandSetGl128() override = default;
+
+    bool needs_home_before_init_regs_for_scan(Genesys_Device* dev) const override;
+
+    void init(Genesys_Device* dev) const override;
+
+    void init_regs_for_warmup(Genesys_Device* dev, const Genesys_Sensor& sensor,
+                              Genesys_Register_Set* regs) const override;
+
+    void init_regs_for_shading(Genesys_Device* dev, const Genesys_Sensor& sensor,
+                               Genesys_Register_Set& regs) const override;
+
+    void init_regs_for_scan_session(Genesys_Device* dev, const Genesys_Sensor& sensor,
+                                    Genesys_Register_Set* reg,
+                                    const ScanSession& session) const override;
+
+    void set_fe(Genesys_Device* dev, const Genesys_Sensor& sensor, std::uint8_t set) const override;
+    void set_powersaving(Genesys_Device* dev, int delay) const override;
+    void save_power(Genesys_Device* dev, bool enable) const override;
+
+    void begin_scan(Genesys_Device* dev, const Genesys_Sensor& sensor,
+                    Genesys_Register_Set* regs, bool start_motor) const override;
+
+    void end_scan(Genesys_Device* dev, Genesys_Register_Set* regs, bool check_stop) const override;
+
+    void send_gamma_table(Genesys_Device* dev, const Genesys_Sensor& sensor) const override;
+
+    void offset_calibration(Genesys_Device* dev, const Genesys_Sensor& sensor,
+                            Genesys_Register_Set& regs) const override;
+
+    void coarse_gain_calibration(Genesys_Device* dev, const Genesys_Sensor& sensor,
+                                 Genesys_Register_Set& regs, int dpi) const override;
+
+    SensorExposure led_calibration(Genesys_Device* dev, const Genesys_Sensor& sensor,
+                                   Genesys_Register_Set& regs) const override;
+
+    void wait_for_motor_stop(Genesys_Device* dev) const override;
+
+    void move_back_home(Genesys_Device* dev, bool wait_until_home) const override;
+
+    void update_hardware_sensors(struct Genesys_Scanner* s) const override;
+
+    void update_home_sensor_gpio(Genesys_Device& dev) const override;
+
+    void load_document(Genesys_Device* dev) const override;
+
+    void detect_document_end(Genesys_Device* dev) const override;
+
+    void eject_document(Genesys_Device* dev) const override;
+
+    void send_shading_data(Genesys_Device* dev, const Genesys_Sensor& sensor, std::uint8_t* data,
+                           int size) const override;
+
+    ScanSession calculate_scan_session(const Genesys_Device* dev,
+                                       const Genesys_Sensor& sensor,
+                                       const Genesys_Settings& settings) const override;
+
+    void asic_boot(Genesys_Device* dev, bool cold) const override;
+
+};
+
+// Resolution the ASIC scans at for a sensor entry: DPISET * 6 (DPISET is
+// asic_dpi / 6 at every resolution in the captures).
+unsigned gl128_asic_dpi(const Genesys_Sensor& sensor);
+
+// Host downsample factor for a requested resolution and its sensor entry:
+// where the ASIC scans at a higher resolution (150 and 300 dpi scan at 600),
+// the host averages factor x factor blocks.
+unsigned gl128_host_downsample(const Genesys_Sensor& sensor, unsigned xres);
+
+} // namespace gl128
+} // namespace genesys
+
+#endif // BACKEND_GENESYS_GL128_H
diff --git a/backend/genesys/gl128_registers.h b/backend/genesys/gl128_registers.h
new file mode 100644
index 0000000..ac0eda7
--- /dev/null
+++ b/backend/genesys/gl128_registers.h
@@ -0,0 +1,133 @@
+/* sane - Scanner Access Now Easy.
+
+   Copyright (C) 2026 vermiculous <vermiculous@disroot.org>
+   Portions derived from pyopticfilm (https://github.com/jboneng/pyopticfilm),
+   Copyright (C) jboneng, used with permission.
+
+   This file is part of the SANE package.
+
+   This program is free software; you can redistribute it and/or
+   modify it under the terms of the GNU General Public License as
+   published by the Free Software Foundation; either version 2 of the
+   License, or (at your option) any later version.
+
+   This program is distributed in the hope that it will be useful, but
+   WITHOUT ANY WARRANTY; without even the implied warranty of
+   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
+   General Public License for more details.
+
+   You should have received a copy of the GNU General Public License
+   along with this program.  If not, see <https://www.gnu.org/licenses/>.
+*/
+
+/*
+ * GL128 register addresses and bit masks, from USB captures of the vendor
+ * driver (as decoded by pyopticfilm's Gl128Registers). GL124-family, but not
+ * identical to GL124: status is at 0x101, and the front end, exposure and
+ * depth registers differ from gl124_registers.h.
+ */
+
+#ifndef BACKEND_GENESYS_GL128_REGISTERS_H
+#define BACKEND_GENESYS_GL128_REGISTERS_H
+
+#include <cstdint>
+
+namespace genesys {
+namespace gl128 {
+
+using RegAddr = std::uint16_t;
+using RegMask = std::uint8_t;
+
+// -- 0x01 scan control --------------------------------------------------
+static constexpr RegAddr REG_0x01 = 0x01;
+static constexpr RegMask REG_0x01_DVDSET = 0x20;
+static constexpr RegMask REG_0x01_STAGGER = 0x10;
+static constexpr RegMask REG_0x01_SHDAREA = 0x02;
+static constexpr RegMask REG_0x01_SCAN = 0x01;
+
+// -- 0x02 motor -----------------------------------------------------------
+static constexpr RegAddr REG_0x02 = 0x02;
+static constexpr RegMask REG_0x02_AGOHOME = 0x20;
+static constexpr RegMask REG_0x02_MTRPWR = 0x10;
+static constexpr RegMask REG_0x02_FASTFED = 0x08;
+static constexpr RegMask REG_0x02_MTRREV = 0x04;
+
+// -- 0x03 lamp --------------------------------------------------------------
+// XPASEL is held for every transparency operation; LAMPPWR gates the white
+// lamp. IR passes clear LAMPPWR and keep XPASEL.
+static constexpr RegAddr REG_0x03 = 0x03;
+static constexpr RegMask REG_0x03_AVEENB = 0x40;
+static constexpr RegMask REG_0x03_XPASEL = 0x20;
+static constexpr RegMask REG_0x03_LAMPPWR = 0x10;
+
+// -- counters / start -------------------------------------------------------
+static constexpr RegAddr REG_CLRCNT = 0x0D;  // write CLRCNT_ALL to clear line/motor/feed counters
+static constexpr RegMask CLRCNT_ALL = 0x07;
+static constexpr RegAddr REG_START = 0x0F;   // write START_GO to launch the configured operation
+static constexpr RegMask START_GO = 0x01;
+
+// -- scan geometry / timing --------------------------------------------------
+static constexpr RegAddr REG_LINCNT = 0x25;    // 24-bit BE, native (7200 dpi) lines
+static constexpr RegAddr REG_LPERIOD = 0x28;   // 24-bit BE line exposure period
+static constexpr RegAddr REG_DPISET = 0x2C;    // 16-bit BE, == effective_dpi / 6
+static constexpr RegAddr REG_DEPTH_A = 0x33;   // 0x04 = 16-bit output, 0x1F = 8-bit
+static constexpr RegMask DEPTH16_A = 0x04;
+static constexpr RegMask DEPTH8_A = 0x1F;
+
+// -- infrared -----------------------------------------------------------------
+// bit 2 enables the IR LED; never read-modify-written
+static constexpr RegAddr REG_IR = 0x37;
+static constexpr RegMask IR_LED = 0x04;
+
+static constexpr RegAddr REG_FEEDL = 0x3D;     // 24-bit BE feed distance, move-only ops
+
+// -- analog frontend ------------------------------------------------------------
+// Front end registers are written as index + value through 0x51/0x5D/0x5E
+// (not 0x3a/0x3b as on GL845).
+static constexpr RegAddr REG_FE_INDEX = 0x51;  // frontend register index
+static constexpr RegAddr REG_FE_HIGH = 0x5D;   // frontend value, high byte
+static constexpr RegAddr REG_FE_LOW = 0x5E;    // frontend value, low byte
+
+static constexpr RegAddr REG_EXPOSURE = 0x7D;  // 24-bit BE base exposure (captures: 14000)
+
+// -- image geometry --------------------------------------------------------------
+static constexpr RegAddr REG_STRPIXEL = 0x82;  // 24-bit BE, native 7200 dpi units
+static constexpr RegAddr REG_ENDPIXEL = 0x85;  // 24-bit BE, native 7200 dpi units
+
+static constexpr RegAddr REG_DEPTH_B = 0xAF;   // 0x46 = 16-bit output, 0xFF = 8-bit
+static constexpr RegMask DEPTH16_B = 0x46;
+static constexpr RegMask DEPTH8_B = 0xFF;
+
+// -- status -------------------------------------------------------------------------
+// High-address read. Bit layout as GL845's 0x41 (GL124 uses 0x100).
+static constexpr RegAddr REG_STATUS = 0x101;
+static constexpr RegMask STATUS_PWRBIT = 0x80;
+static constexpr RegMask STATUS_BUFEMPTY = 0x40;
+static constexpr RegMask STATUS_FEEDFSH = 0x20;
+static constexpr RegMask STATUS_SCANFSH = 0x10;
+static constexpr RegMask STATUS_HOMESNR = 0x08;
+static constexpr RegMask STATUS_LAMPSTS = 0x04;
+static constexpr RegMask STATUS_FEBUSY = 0x02;
+static constexpr RegMask STATUS_MOTORENB = 0x01;
+
+// -- bulk transfer preambles -------------------------------------------------------
+static constexpr std::uint8_t BULK_INDEX_RAM = 0x00;   // RAM / calibration reads
+static constexpr std::uint8_t BULK_INDEX_IMAGE = 0x08; // image stream
+
+// -- AHB windows -------------------------------------------------------------------
+// Per-channel exposure, motor slopes, shading table upload targets.
+static constexpr std::uint32_t AHB_CHANNEL_R = 0x10000000;
+static constexpr std::uint32_t AHB_CHANNEL_G = 0x10004000;
+static constexpr std::uint32_t AHB_CHANNEL_B = 0x10008000;
+static constexpr std::uint32_t AHB_SLOPE_SCAN = 0x1000C000;
+static constexpr std::uint32_t AHB_SLOPE_FAST = 0x10010000;
+static constexpr std::uint32_t AHB_SHADING = 0x10014000;
+
+// -- vendor probe (feed completion polling) ------------------------------------------
+static constexpr std::uint8_t FEED_PROBE_INDEX = 0x21;
+static constexpr std::uint8_t FEED_PROBE_DONE = 0x04;
+
+} // namespace gl128
+} // namespace genesys
+
+#endif // BACKEND_GENESYS_GL128_REGISTERS_H
diff --git a/backend/genesys/gl843.cpp b/backend/genesys/gl843.cpp
index c2f4b52..374b218 100644
--- a/backend/genesys/gl843.cpp
+++ b/backend/genesys/gl843.cpp
@@ -927,46 +927,46 @@ static void gl843_init_optical_regs_scan(Genesys_Device* dev, const Genesys_Sens
     reg->set8(REG_0x2F, 0x7f);
 
   /* monochrome / color scan */
-    switch (session.params.depth) {
+  reg->find_reg(REG_0x04).value &= ~(REG_0x04_LINEART | REG_0x04_BITSET);
+  switch (session.params.depth) {
+    case 1:
+      reg->find_reg(REG_0x04).value |= REG_0x04_LINEART;
+      break;
     case 8:
-            reg->find_reg(REG_0x04).value &= ~(REG_0x04_LINEART | REG_0x04_BITSET);
       break;
     case 16:
-            reg->find_reg(REG_0x04).value &= ~REG_0x04_LINEART;
-            reg->find_reg(REG_0x04).value |= REG_0x04_BITSET;
+      reg->find_reg(REG_0x04).value |= REG_0x04_BITSET;
       break;
-    }
+  }
 
-    reg->find_reg(REG_0x04).value &= ~(REG_0x04_FILTER | REG_0x04_AFEMOD);
-  if (session.params.channels == 1)
-    {
-      switch (session.params.color_filter)
-	{
-            case ColorFilter::RED:
-                reg->find_reg(REG_0x04).value |= 0x14;
-                break;
-            case ColorFilter::BLUE:
-                reg->find_reg(REG_0x04).value |= 0x1c;
-                break;
-            case ColorFilter::GREEN:
-                reg->find_reg(REG_0x04).value |= 0x18;
-                break;
-            default:
-                break; // should not happen
-	}
-    } else {
-        switch (dev->frontend.layout.type) {
-            case FrontendType::WOLFSON:
-                reg->find_reg(REG_0x04).value |= 0x10; // pixel by pixel
-                break;
-            case FrontendType::ANALOG_DEVICES:
-                reg->find_reg(REG_0x04).value |= 0x20; // slow color pixel by pixel
-                break;
-            default:
-                throw SaneException("Invalid frontend type %d",
-                                    static_cast<unsigned>(dev->frontend.layout.type));
-        }
-    }
+  reg->find_reg(REG_0x04).value &= ~(REG_0x04_FILTER | REG_0x04_AFEMOD);
+  if (session.params.channels == 1) {
+    switch (session.params.color_filter) {
+      case ColorFilter::RED:
+        reg->find_reg(REG_0x04).value |= REG_0x04_FILTER_R;
+        break;
+        case ColorFilter::GREEN:
+        reg->find_reg(REG_0x04).value |= REG_0x04_FILTER_G;
+        break;
+      case ColorFilter::BLUE:
+        reg->find_reg(REG_0x04).value |= REG_0x04_FILTER_B;
+        break;
+      default:
+        break; // should not happen
+	  }
+  }
+
+  switch (dev->frontend.layout.type) {
+    case FrontendType::WOLFSON:
+      reg->find_reg(REG_0x04).value |= REG_0x04_AFEMOD_PXP; // pixel by pixel
+      break;
+    case FrontendType::ANALOG_DEVICES:
+      reg->find_reg(REG_0x04).value |= REG_0x04_AFEMOD_SLOW_PXP; // slow color pixel by pixel
+      break;
+    default:
+      throw SaneException("Invalid frontend type %d",
+                          static_cast<unsigned>(dev->frontend.layout.type));
+  }
 
     const auto& dpihw_sensor = sanei_genesys_find_sensor(dev, session.output_resolution,
                                                          session.params.channels,
diff --git a/backend/genesys/gl843_registers.h b/backend/genesys/gl843_registers.h
index a1fe156..adb3a73 100644
--- a/backend/genesys/gl843_registers.h
+++ b/backend/genesys/gl843_registers.h
@@ -58,11 +58,21 @@ static constexpr RegMask REG_0x03_LAMPPWR = 0x10;
 static constexpr RegMask REG_0x03_LAMPTIM = 0x0f;
 
 static constexpr RegAddr REG_0x04 = 0x04;
-static constexpr RegMask REG_0x04_LINEART = 0x80;
-static constexpr RegMask REG_0x04_BITSET = 0x40;
-static constexpr RegMask REG_0x04_AFEMOD = 0x30;
-static constexpr RegMask REG_0x04_FILTER = 0x0c;
-static constexpr RegMask REG_0x04_FESET = 0x03;
+static constexpr RegMask REG_0x04_LINEART         = 1<<7;
+static constexpr RegMask REG_0x04_BITSET          = 1<<6;
+
+static constexpr RegMask REG_0x04_AFEMOD          = 1<<5 | 1<<4;
+static constexpr RegMask REG_0x04_AFEMOD_SLOW_PXP = 1<<5;
+static constexpr RegMask REG_0x04_AFEMOD_PXP      = 1<<4;
+static constexpr RegMask REG_0x04_AFEMOD_MONO     = 0;
+
+static constexpr RegMask REG_0x04_FILTER          = 1<<3 | 1<<2;
+static constexpr RegMask REG_0x04_FILTER_RGB      = 0;
+static constexpr RegMask REG_0x04_FILTER_R        = 1<<2;
+static constexpr RegMask REG_0x04_FILTER_G        = 1<<3;
+static constexpr RegMask REG_0x04_FILTER_B        = 1<<3 | 1<<2;
+
+static constexpr RegMask REG_0x04_FESET           = 1<<1 | 1<<0;
 
 static constexpr RegShift REG_0x04S_AFEMOD = 4;
 
diff --git a/backend/genesys/image_pipeline.cpp b/backend/genesys/image_pipeline.cpp
index 8dae0c5..88812ec 100644
--- a/backend/genesys/image_pipeline.cpp
+++ b/backend/genesys/image_pipeline.cpp
@@ -397,7 +397,8 @@ PixelFormat ImagePipelineNodeSplitMonoLines::get_output_format(PixelFormat input
 }
 
 
-ImagePipelineNodeMergeColorToGray::ImagePipelineNodeMergeColorToGray(ImagePipelineNode& source) :
+ImagePipelineNodeMergeColorToGray::ImagePipelineNodeMergeColorToGray(ImagePipelineNode& source,
+                                                                     ColorFilter filter) :
     source_(source)
 {
 
@@ -405,6 +406,12 @@ ImagePipelineNodeMergeColorToGray::ImagePipelineNodeMergeColorToGray(ImagePipeli
     float red_mult = 0.2125f;
     float green_mult = 0.7154f;
     float blue_mult = 0.0721f;
+    switch (filter) {
+        case ColorFilter::RED: red_mult = 1.0f; green_mult = 0.0f; blue_mult = 0.0f; break;
+        case ColorFilter::GREEN: red_mult = 0.0f; green_mult = 1.0f; blue_mult = 0.0f; break;
+        case ColorFilter::BLUE: red_mult = 0.0f; green_mult = 0.0f; blue_mult = 1.0f; break;
+        default: break;
+    }
 
     switch (get_pixel_format_color_order(source_.get_format())) {
         case ColorOrder::RGB: {
@@ -740,7 +747,8 @@ bool ImagePipelineNodeExtract::get_next_row_data(std::uint8_t* out_data)
             set_raw_pixel_to_row(out_data, i + x_src_width, RawPixel{}, format);
         }
     } else {
-        std::size_t bpp = get_pixel_format_depth(format) / 8;
+        // bytes per pixel, all channels (depth is per channel)
+        std::size_t bpp = get_pixel_format_depth(format) * get_pixel_channels(format) / 8;
         if (x_src_width > 0) {
             std::memcpy(out_data, cached_line_.data() + offset_x_ * bpp,
                         x_src_width * bpp);
diff --git a/backend/genesys/image_pipeline.h b/backend/genesys/image_pipeline.h
index 39aed71..17ccc32 100644
--- a/backend/genesys/image_pipeline.h
+++ b/backend/genesys/image_pipeline.h
@@ -21,6 +21,7 @@
 #ifndef BACKEND_GENESYS_IMAGE_PIPELINE_H
 #define BACKEND_GENESYS_IMAGE_PIPELINE_H
 
+#include "enums.h"
 #include "image.h"
 #include "image_pixel.h"
 #include "image_buffer.h"
@@ -326,7 +327,10 @@ private:
 class ImagePipelineNodeMergeColorToGray : public ImagePipelineNode
 {
 public:
-    ImagePipelineNodeMergeColorToGray(ImagePipelineNode& source);
+    // ColorFilter::NONE mixes the channels to luminance; RED/GREEN/BLUE keeps
+    // only that channel (gray scans on scanners without hardware gray).
+    ImagePipelineNodeMergeColorToGray(ImagePipelineNode& source,
+                                      ColorFilter filter = ColorFilter::NONE);
 
     std::size_t get_width() const override { return source_.get_width(); }
     std::size_t get_height() const override { return source_.get_height(); }
@@ -481,6 +485,149 @@ private:
     std::vector<std::uint8_t> cached_line_;
 };
 
+// Averages each group of `factor` rows. Used for GL128, which samples Y at
+// twice the requested resolution.
+class ImagePipelineNodeAverageRows : public ImagePipelineNode
+{
+public:
+    ImagePipelineNodeAverageRows(ImagePipelineNode& source, std::size_t factor) :
+        source_(source), factor_{factor}
+    {
+        cached_line_.resize(source_.get_row_bytes());
+        sums_.resize(source_.get_width() * get_pixel_channels(source_.get_format()));
+    }
+
+    std::size_t get_width() const override { return source_.get_width(); }
+    std::size_t get_height() const override { return source_.get_height() / factor_; }
+    PixelFormat get_format() const override { return source_.get_format(); }
+
+    bool eof() const override { return source_.eof(); }
+
+    bool get_next_row_data(std::uint8_t* out_data) override
+    {
+        auto format = get_format();
+        unsigned channels = get_pixel_channels(format);
+        std::size_t width = get_width();
+        std::fill(sums_.begin(), sums_.end(), 0u);
+        bool got_data = true;
+        for (std::size_t i = 0; i < factor_; i++) {
+            if (!source_.get_next_row_data(cached_line_.data())) {
+                got_data = false;
+            }
+            for (std::size_t x = 0; x < width; x++) {
+                for (unsigned c = 0; c < channels; c++) {
+                    sums_[x * channels + c] +=
+                            get_raw_channel_from_row(cached_line_.data(), x, c, format);
+                }
+            }
+        }
+        for (std::size_t x = 0; x < width; x++) {
+            for (unsigned c = 0; c < channels; c++) {
+                auto v = (sums_[x * channels + c] + factor_ / 2) / factor_;
+                set_raw_channel_to_row(out_data, x, c, static_cast<std::uint16_t>(v), format);
+            }
+        }
+        return got_data;
+    }
+
+private:
+    ImagePipelineNode& source_;
+    std::size_t factor_ = 1;
+    std::vector<std::uint8_t> cached_line_;
+    std::vector<std::uint32_t> sums_;
+};
+
+// Averages factor x factor pixel blocks; trailing rows and columns that do
+// not fill a block are dropped. Used for GL128 below 600 dpi.
+class ImagePipelineNodeBlockAverage : public ImagePipelineNode
+{
+public:
+    ImagePipelineNodeBlockAverage(ImagePipelineNode& source, std::size_t factor) :
+        source_(source), factor_{factor}
+    {
+        cached_line_.resize(source_.get_row_bytes());
+        sums_.resize(get_width() * get_pixel_channels(source_.get_format()));
+    }
+
+    std::size_t get_width() const override { return source_.get_width() / factor_; }
+    std::size_t get_height() const override { return source_.get_height() / factor_; }
+    PixelFormat get_format() const override { return source_.get_format(); }
+
+    bool eof() const override { return source_.eof(); }
+
+    bool get_next_row_data(std::uint8_t* out_data) override
+    {
+        auto format = get_format();
+        unsigned channels = get_pixel_channels(format);
+        std::size_t width = get_width();
+        std::fill(sums_.begin(), sums_.end(), 0u);
+        bool got_data = true;
+        for (std::size_t i = 0; i < factor_; i++) {
+            if (!source_.get_next_row_data(cached_line_.data())) {
+                got_data = false;
+            }
+            for (std::size_t x = 0; x < width * factor_; x++) {
+                for (unsigned c = 0; c < channels; c++) {
+                    sums_[(x / factor_) * channels + c] +=
+                            get_raw_channel_from_row(cached_line_.data(), x, c, format);
+                }
+            }
+        }
+        const std::size_t count = factor_ * factor_;
+        for (std::size_t x = 0; x < width; x++) {
+            for (unsigned c = 0; c < channels; c++) {
+                auto v = (sums_[x * channels + c] + count / 2) / count;
+                set_raw_channel_to_row(out_data, x, c, static_cast<std::uint16_t>(v), format);
+            }
+        }
+        return got_data;
+    }
+
+private:
+    ImagePipelineNode& source_;
+    std::size_t factor_ = 1;
+
+    std::vector<std::uint8_t> cached_line_;
+    std::vector<std::uint32_t> sums_;
+};
+
+// Mirrors each row in X. Used for GL128, whose lines are mirrored relative
+// to the film.
+class ImagePipelineNodeMirrorX : public ImagePipelineNode
+{
+public:
+    explicit ImagePipelineNodeMirrorX(ImagePipelineNode& source) :
+        source_(source)
+    {
+        cached_line_.resize(source_.get_row_bytes());
+    }
+
+    std::size_t get_width() const override { return source_.get_width(); }
+    std::size_t get_height() const override { return source_.get_height(); }
+    PixelFormat get_format() const override { return source_.get_format(); }
+
+    bool eof() const override { return source_.eof(); }
+
+    bool get_next_row_data(std::uint8_t* out_data) override
+    {
+        bool got_data = source_.get_next_row_data(cached_line_.data());
+        auto format = get_format();
+        unsigned channels = get_pixel_channels(format);
+        std::size_t width = get_width();
+        for (std::size_t x = 0; x < width; x++) {
+            for (unsigned c = 0; c < channels; c++) {
+                set_raw_channel_to_row(out_data, width - 1 - x, c,
+                        get_raw_channel_from_row(cached_line_.data(), x, c, format), format);
+            }
+        }
+        return got_data;
+    }
+
+private:
+    ImagePipelineNode& source_;
+    std::vector<std::uint8_t> cached_line_;
+};
+
 // A pipeline node that mimics the calibration behavior on Genesys chips
 class ImagePipelineNodeCalibrate : public ImagePipelineNode
 {
diff --git a/backend/genesys/low.cpp b/backend/genesys/low.cpp
index 3ffc24a..3846842 100644
--- a/backend/genesys/low.cpp
+++ b/backend/genesys/low.cpp
@@ -35,6 +35,8 @@
 #include "gl646_registers.h"
 
 #include "gl124.h"
+#include "gl128_registers.h"
+#include "gl128.h"
 #include "gl646.h"
 #include "gl841.h"
 #include "gl842.h"
@@ -65,6 +67,7 @@ std::unique_ptr<CommandSet> create_cmd_set(AsicType asic_type)
         case AsicType::GL846: return std::unique_ptr<CommandSet>(new gl846::CommandSetGl846{});
         case AsicType::GL847: return std::unique_ptr<CommandSet>(new gl847::CommandSetGl847{});
         case AsicType::GL124: return std::unique_ptr<CommandSet>(new gl124::CommandSetGl124{});
+        case AsicType::GL128: return std::unique_ptr<CommandSet>(new gl128::CommandSetGl128{});
         default: throw SaneException(SANE_STATUS_INVAL, "unknown ASIC type");
     }
 }
@@ -140,6 +143,7 @@ Status scanner_read_status(Genesys_Device& dev)
 
     switch (dev.model->asic_type) {
         case AsicType::GL124: address = 0x101; break;
+        case AsicType::GL128: address = 0x101; break;
         case AsicType::GL646:
         case AsicType::GL841:
         case AsicType::GL842:
@@ -232,6 +236,7 @@ void sanei_genesys_read_valid_words(Genesys_Device* dev, unsigned int* words)
   switch (dev->model->asic_type)
     {
     case AsicType::GL124:
+    case AsicType::GL128:
             *words = dev->interface->read_register(0x102) & 0x03;
             *words = *words * 256 + dev->interface->read_register(0x103);
             *words = *words * 256 + dev->interface->read_register(0x104);
@@ -273,7 +278,7 @@ void sanei_genesys_read_scancnt(Genesys_Device* dev, unsigned int* words)
 {
     DBG_HELPER(dbg);
 
-    if (dev->model->asic_type == AsicType::GL124) {
+    if (dev->model->asic_type == AsicType::GL124 || dev->model->asic_type == AsicType::GL128) {
         *words = (dev->interface->read_register(0x10b) & 0x0f) << 16;
         *words += (dev->interface->read_register(0x10c) << 8);
         *words += dev->interface->read_register(0x10d);
@@ -541,7 +546,7 @@ void sanei_genesys_read_feed_steps(Genesys_Device* dev, unsigned int* steps)
 {
     DBG_HELPER(dbg);
 
-    if (dev->model->asic_type == AsicType::GL124) {
+    if (dev->model->asic_type == AsicType::GL124 || dev->model->asic_type == AsicType::GL128) {
         *steps = (dev->interface->read_register(0x108) & 0x1f) << 16;
         *steps += (dev->interface->read_register(0x109) << 8);
         *steps += dev->interface->read_register(0x10a);
@@ -1222,6 +1227,24 @@ ImagePipelineStack build_image_pipeline(const Genesys_Device& dev, const ScanSes
         pipeline.push_node<ImagePipelineNodeDebug>(debug_prefix + "_5_after_format.tiff");
     }
 
+    // GL128 samples Y at twice the resolution. The CCD unstagger is given in
+    // these buffer rows (see gl128 calculate_scan_session()) and runs first;
+    // then row pairs are averaged, before the colour line shift.
+    if (dev.model->asic_type == AsicType::GL128 && session.num_staggered_lines > 0) {
+        pipeline.push_node<ImagePipelineNodePixelShiftLines>(session.stagger_y.shifts());
+
+        if (log_image_data) {
+            pipeline.push_node<ImagePipelineNodeDebug>(debug_prefix + "_5b_after_y_unstagger.tiff");
+        }
+    }
+
+    if (dev.model->asic_type == AsicType::GL128 && session.params.lines > 0 &&
+        session.optical_line_count / session.params.lines > 1)
+    {
+        pipeline.push_node<ImagePipelineNodeAverageRows>(
+                session.optical_line_count / session.params.lines);
+    }
+
     if (session.max_color_shift_lines > 0 && session.params.channels == 3) {
         pipeline.push_node<ImagePipelineNodeComponentShiftLines>(
                     session.color_shift_lines_r,
@@ -1243,7 +1266,7 @@ ImagePipelineStack build_image_pipeline(const Genesys_Device& dev, const ScanSes
         }
     }
 
-    if (session.num_staggered_lines > 0) {
+    if (session.num_staggered_lines > 0 && dev.model->asic_type != AsicType::GL128) {
         pipeline.push_node<ImagePipelineNodePixelShiftLines>(session.stagger_y.shifts());
 
         if (log_image_data) {
@@ -1251,6 +1274,18 @@ ImagePipelineStack build_image_pipeline(const Genesys_Device& dev, const ScanSes
         }
     }
 
+    // GL128 below 600 dpi: the scan runs at 600 dpi; average down to the
+    // requested resolution after the line shifts.
+    if (dev.model->asic_type == AsicType::GL128) {
+        const auto& sensor = sanei_genesys_find_sensor(&dev, session.params.xres,
+                                                       session.params.channels,
+                                                       session.params.scan_method);
+        unsigned factor = gl128::gl128_host_downsample(sensor, session.params.xres);
+        if (factor > 1) {
+            pipeline.push_node<ImagePipelineNodeBlockAverage>(factor);
+        }
+    }
+
     if (session.use_host_side_calib &&
         !has_flag(dev.model->flags, ModelFlag::DISABLE_SHADING_CALIBRATION) &&
         !has_flag(session.params.flags, ScanFlag::DISABLE_SHADING))
@@ -1266,17 +1301,34 @@ ImagePipelineStack build_image_pipeline(const Genesys_Device& dev, const ScanSes
     }
 
     if (session.use_host_side_gray) {
-        pipeline.push_node<ImagePipelineNodeMergeColorToGray>();
+        // ModelFlag::HOST_SIDE_GRAY uses ColorFilter::NONE (luminance); GL128
+        // gray keeps the selected filter's channel.
+        pipeline.push_node<ImagePipelineNodeMergeColorToGray>(session.params.color_filter);
 
         if (log_image_data) {
             pipeline.push_node<ImagePipelineNodeDebug>(debug_prefix + "_10_after_nogray.tiff");
         }
     }
 
+    // GL128 rounds the scan width up to its alignment (see
+    // calculate_scan_session()); crop the surplus columns at the native end
+    // rather than rescaling the row.
+    if (dev.model->asic_type == AsicType::GL128 &&
+        pipeline.get_output_width() > session.params.get_requested_pixels())
+    {
+        pipeline.push_node<ImagePipelineNodeExtract>(0, 0,
+                session.params.get_requested_pixels(), pipeline.get_output_height());
+    }
+
     if (pipeline.get_output_width() != session.params.get_requested_pixels()) {
         pipeline.push_node<ImagePipelineNodeScaleRows>(session.params.get_requested_pixels());
     }
 
+    // GL128 lines are mirrored in X relative to the film.
+    if (dev.model->asic_type == AsicType::GL128) {
+        pipeline.push_node<ImagePipelineNodeMirrorX>();
+    }
+
     return pipeline;
 }
 
@@ -1468,7 +1520,11 @@ void sanei_genesys_asic_init(Genesys_Device* dev)
             dev->set_head_pos_unknown(ScanHeadId::SECONDARY);
         }
     }
-    dev->cmd_set->move_back_home(dev, true);
+    // GL128 has no standalone home seek; the carriage parks at the end of
+    // every scan.
+    if (dev->model->asic_type != AsicType::GL128) {
+        dev->cmd_set->move_back_home(dev, true);
+    }
 
     // Set powersaving (default = 15 minutes)
     dev->cmd_set->set_powersaving(dev, 15);
@@ -1486,6 +1542,7 @@ void scanner_start_action(Genesys_Device& dev, bool start_motor)
         case AsicType::GL846:
         case AsicType::GL847:
         case AsicType::GL124:
+        case AsicType::GL128:
             break;
         default:
             throw SaneException("Unsupported chip");
@@ -1537,6 +1594,12 @@ void regs_set_exposure(AsicType asic_type, Genesys_Register_Set& regs,
             regs.set24(gl124::REG_EXPB, exposure.blue);
             break;
         }
+        case AsicType::GL128: {
+            // One exposure register for all channels.
+            regs.set24(gl128::REG_EXPOSURE,
+                      std::max(std::max(exposure.red, exposure.green), exposure.blue));
+            break;
+        }
         case AsicType::GL646: {
             regs.set16(gl646::REG_EXPR, exposure.red);
             regs.set16(gl646::REG_EXPG, exposure.green);
@@ -1612,6 +1675,10 @@ void regs_set_optical_off(AsicType asic_type, Genesys_Register_Set& regs)
             regs.find_reg(gl124::REG_0x01).value &= ~gl124::REG_0x01_SCAN;
             break;
         }
+        case AsicType::GL128: {
+            regs.find_reg(gl128::REG_0x01).value &= ~gl128::REG_0x01_SCAN;
+            break;
+        }
         default:
             throw SaneException("Unsupported asic");
     }
diff --git a/backend/genesys/motor.cpp b/backend/genesys/motor.cpp
index 1dfe64f..9a5d992 100644
--- a/backend/genesys/motor.cpp
+++ b/backend/genesys/motor.cpp
@@ -30,6 +30,11 @@ namespace genesys {
 
 unsigned MotorSlope::get_table_step_shifted(unsigned step, StepType step_type) const
 {
+    if (!table.empty()) {
+        // The table is already for the profile's step type.
+        return table[std::min<std::size_t>(step, table.size() - 1)];
+    }
+
     // first two steps are always equal to the initial speed
     if (step < 2) {
         return initial_speed_w >> static_cast<unsigned>(step_type);
@@ -59,6 +64,21 @@ MotorSlope MotorSlope::create_from_steps(unsigned initial_w, unsigned max_w,
     return slope;
 }
 
+MotorSlope MotorSlope::create_from_table(const std::vector<std::uint16_t>& table,
+                                         StepType step_type)
+{
+    if (table.empty()) {
+        throw SaneException("Empty motor slope table");
+    }
+    unsigned step_shift = static_cast<unsigned>(step_type);
+    MotorSlope slope;
+    slope.initial_speed_w = static_cast<unsigned>(table.front()) << step_shift;
+    slope.max_speed_w = static_cast<unsigned>(table.back()) << step_shift;
+    slope.max_step_count = static_cast<unsigned>(table.size());
+    slope.table = table;
+    return slope;
+}
+
 void MotorSlopeTable::slice_steps(unsigned count, unsigned step_multiplier)
 {
     if (count > table.size() || count < step_multiplier) {
@@ -157,6 +177,7 @@ std::ostream& operator<<(std::ostream& out, const MotorSlope& slope)
         << "    initial_speed_w: " << slope.initial_speed_w << '\n'
         << "    max_speed_w: " << slope.max_speed_w << '\n'
         << "    a: " << slope.acceleration << '\n'
+        << "    table size: " << slope.table.size() << '\n'
         << '}';
     return out;
 }
diff --git a/backend/genesys/motor.h b/backend/genesys/motor.h
index 1981e80..d7e683f 100644
--- a/backend/genesys/motor.h
+++ b/backend/genesys/motor.h
@@ -94,10 +94,20 @@ struct MotorSlope
     // acceleration in steps per pixeltime squared.
     float acceleration = 0;
 
+    // Optional exact slope table (pixeltime per step, already for the profile's step type),
+    // for motors whose vendor driver uses a ramp that does not follow the model above. When
+    // set, it is used as is instead of the formula; steps past its end use the last value.
+    std::vector<std::uint16_t> table;
+
     unsigned get_table_step_shifted(unsigned step, StepType step_type) const;
 
     static MotorSlope create_from_steps(unsigned initial_w, unsigned max_w,
                                         unsigned steps);
+
+    // initial_speed_w and max_speed_w are set to the table's first and last values scaled back
+    // to full steps, so that code comparing them with shifted values stays consistent.
+    static MotorSlope create_from_table(const std::vector<std::uint16_t>& table,
+                                        StepType step_type);
 };
 
 struct MotorSlopeTable
diff --git a/backend/genesys/scanner_interface_usb.cpp b/backend/genesys/scanner_interface_usb.cpp
index 542d4ff..e1fcbf7 100644
--- a/backend/genesys/scanner_interface_usb.cpp
+++ b/backend/genesys/scanner_interface_usb.cpp
@@ -43,7 +43,8 @@ std::uint8_t ScannerInterfaceUsb::read_register(std::uint16_t address)
     if (dev_->model->asic_type == AsicType::GL847 ||
         dev_->model->asic_type == AsicType::GL845 ||
         dev_->model->asic_type == AsicType::GL846 ||
-        dev_->model->asic_type == AsicType::GL124)
+        dev_->model->asic_type == AsicType::GL124 ||
+        dev_->model->asic_type == AsicType::GL128)
     {
         std::uint8_t value2x8[2];
         std::uint16_t address16 = 0x22 + (address << 8);
@@ -88,7 +89,8 @@ void ScannerInterfaceUsb::write_register(std::uint16_t address, std::uint8_t val
     if (dev_->model->asic_type == AsicType::GL847 ||
         dev_->model->asic_type == AsicType::GL845 ||
         dev_->model->asic_type == AsicType::GL846 ||
-        dev_->model->asic_type == AsicType::GL124)
+        dev_->model->asic_type == AsicType::GL124 ||
+        dev_->model->asic_type == AsicType::GL128)
     {
         std::uint8_t buffer[2];
 
@@ -189,7 +191,8 @@ static void bulk_read_data_send_header(UsbDevice& usb_dev, AsicType asic_type, s
     if (asic_type == AsicType::GL124 ||
         asic_type == AsicType::GL845 ||
         asic_type == AsicType::GL846 ||
-        asic_type == AsicType::GL847)
+        asic_type == AsicType::GL847 ||
+        asic_type == AsicType::GL128)
     {
         // hard coded 0x10000000 address
         outdata[0] = 0;
@@ -231,7 +234,8 @@ void ScannerInterfaceUsb::bulk_read_data(std::uint8_t addr, std::uint8_t* data,
     if (dev_->model->asic_type == AsicType::GL124 ||
         dev_->model->asic_type == AsicType::GL845 ||
         dev_->model->asic_type == AsicType::GL846 ||
-        dev_->model->asic_type == AsicType::GL847)
+        dev_->model->asic_type == AsicType::GL847 ||
+        dev_->model->asic_type == AsicType::GL128)
     {
         is_addr_used = 0;
         has_header_before_each_chunk = 1;
@@ -384,7 +388,8 @@ void ScannerInterfaceUsb::write_ahb(std::uint32_t addr, std::uint32_t size, std:
     if (dev_->model->asic_type != AsicType::GL845 &&
         dev_->model->asic_type != AsicType::GL846 &&
         dev_->model->asic_type != AsicType::GL847 &&
-        dev_->model->asic_type != AsicType::GL124)
+        dev_->model->asic_type != AsicType::GL124 &&
+        dev_->model->asic_type != AsicType::GL128)
     {
         throw SaneException("Unsupported transfer type");
     }
@@ -438,7 +443,7 @@ void ScannerInterfaceUsb::write_fe_register(std::uint8_t address, std::uint16_t
     Genesys_Register_Set reg(Genesys_Register_Set::SEQUENTIAL);
 
     reg.init_reg(0x51, address);
-    if (dev_->model->asic_type == AsicType::GL124) {
+    if (dev_->model->asic_type == AsicType::GL124 || dev_->model->asic_type == AsicType::GL128) {
         reg.init_reg(0x5d, (value / 256) & 0xff);
         reg.init_reg(0x5e, value & 0xff);
     } else {
diff --git a/backend/genesys/tables_frontend.cpp b/backend/genesys/tables_frontend.cpp
index 65fc7f4..80aea93 100644
--- a/backend/genesys/tables_frontend.cpp
+++ b/backend/genesys/tables_frontend.cpp
@@ -498,14 +498,14 @@ void genesys_init_frontend_tables()
     fe.id = AdcId::PLUSTEK_OPTICFILM_7300;
     fe.layout = analog_devices;
     fe.regs = {
-        { 0x00, 0xf8 },
-        { 0x01, 0x80 },
-        { 0x02, 0x10 },
-        { 0x03, 0x06 },
-        { 0x04, 0x06 },
-        { 0x05, 0x09 },
-        { 0x06, 0x0a },
-        { 0x07, 0x0102 },
+        { 0x00, 0xf8 },   // set INPUT_RNG=4V, VREF=internal, 3CH=on, CDS mode, and CLAMP=4V
+        { 0x01, 0x80 },   // set mux order to RGB; red/green/blue are ignored when 3CH=on
+        { 0x02, 0x10 },   // set red gain
+        { 0x03, 0x06 },   // set green gain
+        { 0x04, 0x06 },   // set blue gain
+        { 0x05, 0x09 },   // set +10.8mV red offset
+        { 0x06, 0x0a },   // set +12.0mV green offset
+        { 0x07, 0x0102 }, // set -2.4mV blue offset
     };
     fe.reg2 = {0x00, 0x00, 0x00};
     s_frontends->push_back(fe);
@@ -515,14 +515,14 @@ void genesys_init_frontend_tables()
     fe.id = AdcId::PLUSTEK_OPTICFILM_7400;
     fe.layout = analog_devices;
     fe.regs = {
-        { 0x00, 0xf8 },
-        { 0x01, 0x80 },
-        { 0x02, 0x1f },
-        { 0x03, 0x14 },
-        { 0x04, 0x19 },
-        { 0x05, 0x1b },
-        { 0x06, 0x1e },
-        { 0x07, 0x0e },
+        { 0x00, 0xf8 }, // set INPUT_RNG=4V, VREF=internal, 3CH=on, CDS mode, and CLAMP=4V
+        { 0x01, 0x80 }, // set mux order to RGB; red/green/blue are ignored when 3CH=on
+        { 0x02, 0x1f }, // set red gain
+        { 0x03, 0x14 }, // set green gain
+        { 0x04, 0x19 }, // set blue gain
+        { 0x05, 0x1b }, // set red offset
+        { 0x06, 0x1e }, // set green offset
+        { 0x07, 0x0e }, // set blue offset
     };
     fe.reg2 = {0x00, 0x00, 0x00};
     s_frontends->push_back(fe);
@@ -560,6 +560,29 @@ void genesys_init_frontend_tables()
     };
     fe.reg2 = {0x00, 0x00, 0x00};
     s_frontends->push_back(fe);
+    fe = Genesys_Frontend();
+    fe.id = AdcId::PLUSTEK_OPTICFILM_8200I_SE;
+    // Boot values (pyopticfilm FRONTEND_REGS); offsets 0x02-0x04 and gains
+    // 0x05-0x07 are set by gl128.cpp before every image pass.
+    {
+        GenesysFrontendLayout gl128_fe_layout;
+        gl128_fe_layout.type = FrontendType::ANALOG_DEVICES;
+        gl128_fe_layout.offset_addr = { 0x02, 0x03, 0x04 };
+        gl128_fe_layout.gain_addr = { 0x05, 0x06, 0x07 };
+        fe.layout = gl128_fe_layout;
+    }
+    fe.regs = {
+        { 0x00, 0x00f8 },
+        { 0x01, 0x0080 },
+        { 0x02, 0x0000 },
+        { 0x03, 0x0000 },
+        { 0x04, 0x0000 },
+        { 0x05, 0x0000 },
+        { 0x06, 0x0000 },
+        { 0x07, 0x0000 },
+    };
+    fe.reg2 = {0x00, 0x00, 0x00};
+    s_frontends->push_back(fe);
 
 
     fe = Genesys_Frontend();
diff --git a/backend/genesys/tables_gpo.cpp b/backend/genesys/tables_gpo.cpp
index f129262..228cbcc 100644
--- a/backend/genesys/tables_gpo.cpp
+++ b/backend/genesys/tables_gpo.cpp
@@ -379,6 +379,16 @@ void genesys_init_gpo_tables()
         { 0xa6, 0x00 }, { 0xa7, 0x07 }, { 0xa8, 0x20 }, { 0xa9, 0x01 },
     };
     s_gpo->push_back(gpo);
+    gpo = Genesys_Gpo();
+    gpo.id = GpioId::PLUSTEK_OPTICFILM_8200I_SE;
+    // GPO registers at boot (pyopticfilm GPO_REGS). gl128.cpp writes them in
+    // asic_boot(); this entry is for the table lookup.
+    gpo.regs = {
+        { 0xa2, 0x00 }, { 0xa3, 0x00 }, { 0xa4, 0x00 },
+        { 0xa6, 0x00 }, { 0xa7, 0x00 }, { 0xa8, 0x00 }, { 0xa9, 0x00 },
+        { 0xaa, 0x00 }, { 0xac, 0x00 }, { 0xad, 0x01 }, { 0xae, 0x00 },
+    };
+    s_gpo->push_back(gpo);
 
 
     gpo = Genesys_Gpo();
diff --git a/backend/genesys/tables_model.cpp b/backend/genesys/tables_model.cpp
index 9c55165..f1a200c 100644
--- a/backend/genesys/tables_model.cpp
+++ b/backend/genesys/tables_model.cpp
@@ -2523,8 +2523,28 @@ void genesys_init_usb_device_tables()
     // same as 7300, same USB ID as 7400-v2
     model.name = "plustek-opticfilm-7400-v1";
     model.model = "OpticFilm 7400 (v1)";
-    s_usb_devices->emplace_back(0x07b3, 0x0c3a, 0x0400, model);
+    model.flags = ModelFlag::WARMUP |
+                 ModelFlag::DISABLE_SHADING_CALIBRATION;
+    model.sensor_id = SensorId::CCD_PLUSTEK_OPTICFILM_7400_V1;
+    model.bpp_gray_values = {8, 16};
+    model.bpp_color_values = {8, 16};
+    model.resolutions = {
+        {
+            {ScanMethod::TRANSPARENCY},
+            {7200, 3600, 2400, 1200, 900, 600},
+            {7200, 3600, 2400, 1200, 900, 600},
+        }};
 
+    model.x_offset_ta = 0.0;
+    model.y_offset_ta = 29.0;
+    model.x_size_ta = 39.0;
+    model.y_size_ta = 25.5;
+
+    model.y_offset_calib_white_ta = 0.0;
+    model.y_offset_calib_black_ta = 7;
+    model.y_size_calib_ta_mm = 2.0;
+
+    s_usb_devices->emplace_back(0x07b3, 0x0c3a, 0x0400, model);
 
     model = Genesys_Model();
     model.name = "plustek-opticfilm-7400-v2";
@@ -2577,7 +2597,7 @@ void genesys_init_usb_device_tables()
     model.is_cis = false;
     model.is_sheetfed = false;
 
-    model.sensor_id = SensorId::CCD_PLUSTEK_OPTICFILM_7400;
+    model.sensor_id = SensorId::CCD_PLUSTEK_OPTICFILM_7400_V2;
     model.adc_id = AdcId::PLUSTEK_OPTICFILM_7400;
     model.gpio_id = GpioId::PLUSTEK_OPTICFILM_7400;
     model.motor_id = MotorId::PLUSTEK_OPTICFILM_7400;
@@ -2674,9 +2694,14 @@ void genesys_init_usb_device_tables()
     s_usb_devices->emplace_back(0x07b3, 0x0c13, model);
 
 
-    // same as 7500i
+    // same as 7500i, with full scan area and stock exposure values
     model.name = "plustek-opticfilm-7600i-v1";
     model.model = "OpticFilm 7600i (v1)";
+    model.sensor_id = SensorId::CCD_PLUSTEK_OPTICFILM_7600I_V1;
+    model.x_offset_ta = 0.211667;
+    model.x_size_ta = 36.613833;
+    model.y_size_ta = 24.727;
+    model.x_size_calib_mm = 36.825;
     s_usb_devices->emplace_back(0x07b3, 0x0c3b, 0x0400, model);
 
 
@@ -2748,6 +2773,83 @@ void genesys_init_usb_device_tables()
     model.name = "plustek-opticfilm-7600i-v2";
     model.model = "OpticFilm 7600i (v2)";
     s_usb_devices->emplace_back(0x07b3, 0x0c3b, 0x0605, model);
+    // OpticFilm 8200i SE: GL128 instead of the 8200i's GL845 (USB 0x130d);
+    // the scanner itself is labelled "8200i". Values from USB captures of the
+    // vendor driver (largely as decoded by pyopticfilm).
+    model = Genesys_Model();
+    model.name = "plustek-opticfilm-8200i-se";
+    model.vendor = "PLUSTEK";
+    model.model = "OpticFilm 8200i SE";
+    model.model_id = ModelId::PLUSTEK_OPTICFILM_8200I_SE;
+    model.asic_type = AsicType::GL128;
+
+    // SilverFast's resolutions; 150 and 300 dpi scan at 600 and are averaged
+    // on the host. Infrared is not supported yet.
+    model.resolutions = {
+        {
+            { ScanMethod::TRANSPARENCY },
+            { 7200, 3600, 2400, 1800, 1440, 1200, 900, 720, 600, 300, 150 },
+            { 7200, 3600, 2400, 1800, 1440, 1200, 900, 720, 600, 300, 150 },
+        }
+    };
+
+    // Linear 16-bit output only.
+    model.bpp_gray_values = { 16 };
+    model.bpp_color_values = { 16 };
+    model.default_method = ScanMethod::TRANSPARENCY;
+
+    // Transparency-only scanner: the flatbed geometry and the calibration
+    // areas below are not used (shading is done by the ASIC, see gl128.cpp).
+    model.x_offset = 0.0;
+    model.y_offset = 0.0;
+    model.x_size = 36.0;
+    model.y_size = 44.0;
+
+    model.y_offset_calib_white = 0.0;
+    model.y_size_calib_mm = 0.0;
+    model.x_offset_calib_black = 6.5;
+    model.x_size_calib_mm = 36.83;
+
+    model.x_offset_ta = 0.43;
+    model.y_offset_ta = 28.5;
+    model.x_size_ta = 36.58;
+    // The image may only run to where SilverFast's own full-frame passes end,
+    // about 25.02 mm below the top of the 25.59 mm scan window; offer 25 mm
+    // (a full 24 mm frame), so the default area scans.
+    model.y_size_ta = 25.0;
+
+    model.y_offset_sensor_to_ta = 0.0;
+    model.y_offset_calib_black_ta = 6.5;
+    model.y_offset_calib_white_ta = 0.0;
+    model.y_size_calib_ta_mm = 2.0;
+
+    model.post_scan = 0.0;
+    model.eject_feed = 0.0;
+
+    // Colour line shift at 7200 dpi (the 8200i's GL845 sensor uses 0/12/24).
+    model.ld_shift_r = 0;
+    model.ld_shift_g = 24;
+    model.ld_shift_b = 48;
+
+    model.line_mode_color_order = ColorOrder::RGB;
+
+    model.is_cis = false;
+    model.is_sheetfed = false;
+    model.sensor_id = SensorId::CCD_PLUSTEK_OPTICFILM_8200I_SE;
+    model.adc_id = AdcId::PLUSTEK_OPTICFILM_8200I_SE;
+    model.gpio_id = GpioId::PLUSTEK_OPTICFILM_8200I_SE;
+    model.motor_id = MotorId::PLUSTEK_OPTICFILM_8200I_SE;
+
+    // The front end and shading are programmed by gl128.cpp before every
+    // image pass. UNTESTED until the session tests have reference output.
+    model.flags = ModelFlag::UNTESTED |
+                  ModelFlag::UTA_NO_SECONDARY_MOTOR |
+                  ModelFlag::DISABLE_SHADING_CALIBRATION |
+                  ModelFlag::DISABLE_ADC_CALIBRATION;
+
+    model.search_lines = 200;
+
+    s_usb_devices->emplace_back(0x07b3, 0x1825, model);
 
 
     model = Genesys_Model();
diff --git a/backend/genesys/tables_motor.cpp b/backend/genesys/tables_motor.cpp
index 3cc576f..eb453ab 100644
--- a/backend/genesys/tables_motor.cpp
+++ b/backend/genesys/tables_motor.cpp
@@ -588,6 +588,72 @@ void genesys_init_motor_tables()
     motor.profiles.push_back(profile);
     motor.fast_profiles.push_back(profile);
     s_motors->push_back(std::move(motor));
+    motor = Genesys_Motor();
+    motor.id = MotorId::PLUSTEK_OPTICFILM_8200I_SE;
+    motor.base_ydpi = 7200;
+
+    // SilverFast's two slope tables, exactly as its driver uploads them (USB captures): they
+    // follow no constant-acceleration ramp, so they are given as tables. The fast one is used
+    // for the calibration strips and the second positioning feed, the slow one for the first.
+    profile = MotorProfile();
+    profile.slope = MotorSlope::create_from_table({
+        5854, 1755, 1344, 1150, 1030, 945, 881, 830, 788, 754, 724, 698,
+        675, 654, 636, 619, 604, 590, 577, 565, 554, 544, 534, 525,
+        517, 509, 501, 494, 487, 480, 474, 468, 462, 457, 452, 447,
+        442, 437, 433, 428, 424, 420, 416, 413, 409, 405, 402, 399,
+        396, 392, 389, 386, 384, 381, 378, 375, 373, 370, 368, 365,
+        363, 361, 358, 356, 354, 352, 350, 348, 346, 344, 342, 340,
+        338, 337, 335, 333, 331, 330, 328, 326, 325, 323, 322, 320,
+        319, 317, 316, 315, 313, 312, 310, 309, 308, 307, 305, 304,
+        303, 302, 300, 299, 298, 297, 296, 295, 294, 293, 292, 290,
+        289, 288, 287, 286, 285, 284, 283, 282, 282, 281, 280, 279,
+        278, 277, 276, 275, 274, 274, 273, 272, 271, 270, 269, 269,
+        268, 267, 266, 266, 265, 264, 263, 263, 262, 261, 260, 260,
+        259, 258, 258, 257, 256, 256, 255, 254, 254, 253, 252, 252,
+        251, 251, 250, 249, 249, 248, 248, 247, 246, 246, 245, 245,
+        244, 244, 243, 242, 242, 241, 241, 240, 240, 239, 239, 238,
+        238, 237, 237, 236, 236, 235, 235, 234, 234, 233, 233, 232,
+        232, 231, 231, 230, 230, 230, 229, 229, 228, 228, 227, 227,
+        227, 226, 226, 225, 225, 224, 224, 224, 223, 223, 222, 222,
+        222, 221, 221, 220, 220, 220, 219, 219, 218, 218, 218, 217,
+        217, 217, 216, 216, 216, 215, 215, 214, 214, 214, 213, 213,
+        213, 212, 212, 212, 211, 211, 211, 210, 210, 210, 209, 209,
+        209, 208, 208, 208,
+    }, StepType::QUARTER);
+    profile.step_type = StepType::QUARTER;
+    profile.motor_vref = 3;
+    motor.fast_profiles.push_back(profile);
+
+    profile = MotorProfile();
+    profile.slope = MotorSlope::create_from_table({
+        8116, 4863, 4006, 3581, 3306, 3105, 2955, 2828, 2726, 2639, 2561, 2495,
+        2436, 2383, 2334, 2289, 2248, 2210, 2175, 2144, 2113, 2085, 2057, 2032,
+        2009, 1985, 1965, 1944, 1924, 1905, 1888, 1871, 1854, 1839, 1823, 1808,
+        1794, 1781, 1768, 1755, 1743, 1731, 1719, 1708, 1697, 1686, 1676, 1666,
+        1656, 1647, 1638, 1629, 1620, 1611, 1603, 1595, 1587, 1580, 1572, 1564,
+        1557, 1549, 1543, 1536, 1529, 1523, 1516, 1510, 1504, 1497, 1492, 1486,
+        1480, 1474, 1469, 1463, 1458, 1453, 1447, 1442, 1437, 1432, 1427, 1422,
+        1418, 1414, 1409, 1404, 1400, 1395, 1391, 1387, 1382, 1378, 1375, 1370,
+        1366, 1363, 1358, 1355, 1351, 1347, 1344, 1340, 1336, 1333, 1329, 1326,
+        1322, 1319, 1315, 1313, 1309, 1306, 1302, 1300, 1296, 1293, 1290, 1287,
+        1284, 1281, 1278, 1275, 1272, 1270, 1267, 1264, 1261, 1258, 1256, 1253,
+        1251, 1248, 1245, 1243, 1240, 1238, 1235, 1233, 1230, 1228, 1226, 1223,
+        1221, 1218, 1216, 1214, 1211, 1209, 1207, 1205, 1203, 1200, 1198, 1196,
+        1194, 1192, 1189, 1188, 1185, 1183, 1182, 1179, 1177, 1175, 1173, 1172,
+        1169, 1168, 1166, 1164, 1162, 1160, 1158, 1156, 1154, 1153, 1151, 1149,
+        1147, 1145, 1144, 1142, 1140, 1138, 1137, 1135, 1133, 1132, 1130, 1129,
+        1127, 1125, 1124, 1122, 1121, 1119, 1117, 1116, 1114, 1113, 1111, 1110,
+        1108, 1107, 1105, 1104, 1102, 1101, 1099, 1098, 1096, 1095, 1094, 1092,
+        1091, 1089, 1088, 1086, 1085, 1084, 1082, 1081, 1079, 1078, 1077, 1076,
+        1074, 1073, 1072, 1071, 1069, 1068, 1067, 1065, 1064, 1063, 1062, 1060,
+        1059, 1058, 1057, 1055, 1054, 1053, 1052, 1051, 1049, 1048, 1047, 1046,
+        1045, 1044, 1042, 1041,
+    }, StepType::QUARTER);
+    profile.step_type = StepType::QUARTER;
+    profile.motor_vref = 3;
+    motor.profiles.push_back(profile);
+
+    s_motors->push_back(std::move(motor));
 
 
     motor = Genesys_Motor();
diff --git a/backend/genesys/tables_sensor.cpp b/backend/genesys/tables_sensor.cpp
index fb18abc..4c307cb 100644
--- a/backend/genesys/tables_sensor.cpp
+++ b/backend/genesys/tables_sensor.cpp
@@ -3426,9 +3426,43 @@ void genesys_init_sensor_tables()
         }
     }
 
+    // the 7400 v1 is mostly an opticfilm 7300, but with different DPI support
+    // and a sensor more like the opticfilm 7400 v2.
+    sensor.sensor_id = SensorId::CCD_PLUSTEK_OPTICFILM_7400_V1;
+    sensor.exposure = SensorExposure(0xabe0, 0x80e8, 0x2af8);
+    sensor.exposure_lperiod = 0x8000;
+
+    {
+        struct CustomSensorSettings
+        {
+            ValueFilterAny<unsigned> resolutions;
+            unsigned shading_resolution;
+            int output_pixel_offset;
+            unsigned register_dpiset;
+            StaggerConfig stagger_y;
+        };
+
+        CustomSensorSettings custom_settings[] = {
+            { { 600 }, 600, 2, 100, StaggerConfig{} },
+            { { 900 }, 900, 0, 150, StaggerConfig{} },
+            { { 1200 }, 1200, 0, 200, StaggerConfig{} },
+            { { 2400 }, 2400, 10, 400, StaggerConfig{1, 0} },
+            { { 3600 }, 3600, 20, 600, StaggerConfig{} },
+            { { 7200 }, 7200, 20, 1200, StaggerConfig{4, 0} },
+        };
+
+        for (const CustomSensorSettings& setting : custom_settings) {
+            sensor.resolutions = setting.resolutions;
+            sensor.shading_resolution = setting.shading_resolution;
+            sensor.output_pixel_offset = setting.output_pixel_offset;
+            sensor.register_dpiset = setting.register_dpiset;
+            sensor.stagger_y = setting.stagger_y;
+            s_sensors->push_back(sensor);
+        }
+    }
 
     sensor = Genesys_Sensor();
-    sensor.sensor_id = SensorId::CCD_PLUSTEK_OPTICFILM_7400; // gl845
+    sensor.sensor_id = SensorId::CCD_PLUSTEK_OPTICFILM_7400_V2; // gl845
     sensor.full_resolution = 7200;
     sensor.method = ScanMethod::TRANSPARENCY;
     sensor.register_dpihw = 1200;
@@ -3564,6 +3598,18 @@ void genesys_init_sensor_tables()
         }
     }
 
+    // 7600i v1: 7500i sensor with stock exposure values
+    {
+        std::vector<Genesys_Sensor> v1_sensors;
+        for (const auto& s : *s_sensors) {
+            if (s.sensor_id == SensorId::CCD_PLUSTEK_OPTICFILM_7500I) {
+                v1_sensors.push_back(s);
+                v1_sensors.back().sensor_id = SensorId::CCD_PLUSTEK_OPTICFILM_7600I_V1;
+                v1_sensors.back().exposure_lperiod = 0x36b0;
+            }
+        }
+        s_sensors->insert(s_sensors->end(), v1_sensors.begin(), v1_sensors.end());
+    }
 
     sensor = Genesys_Sensor();
     sensor.sensor_id = SensorId::CCD_PLUSTEK_OPTICFILM_8200I; // gl845
@@ -3623,6 +3669,85 @@ void genesys_init_sensor_tables()
     }
 
 
+    sensor = Genesys_Sensor();
+    sensor.sensor_id = SensorId::CCD_PLUSTEK_OPTICFILM_8200I_SE; // gl128
+    sensor.full_resolution = 7200;
+    sensor.register_dpihw = 1200;
+    // Not used: genesys' offset, gain and shading calibration are disabled for
+    // this model; gl128.cpp calibrates in the ASIC.
+    sensor.black_pixels = 0;
+    sensor.fau_gain_white_ref = 0;
+    sensor.gain_white_ref = 0;
+    sensor.exposure = { 0x0000, 0x0000, 0x0000 };
+    sensor.gamma = { 1.0f, 1.0f, 1.0f };
+    // Shading is done by the ASIC (see gl128.cpp); the model disables
+    // genesys' shading calibration.
+    sensor.use_host_side_calib = true;
+    // Registers SilverFast sets before every acquisition, at every resolution
+    // (pyopticfilm SCAN_REGS).
+    sensor.custom_regs = {
+        { 0x04, 0x42 }, { 0x05, 0x40 }, { 0x06, 0xf0 }, { 0x0b, 0x4c },
+        { 0x1c, 0x20 }, { 0x1d, 0x80 }, { 0x1e, 0x20 },
+        { 0x3b, 0x01 },
+        { 0x52, 0x0b }, { 0x53, 0x0d }, { 0x54, 0x0f }, { 0x55, 0x01 },
+        { 0x56, 0x05 }, { 0x57, 0x07 },
+        { 0x5a, 0x31 }, { 0x5b, 0x79 },
+        { 0x70, 0x0a }, { 0x71, 0x0b }, { 0x72, 0x0c }, { 0x73, 0x0d },
+        { 0x81, 0x40 },
+        { 0x8a, 0x00 }, { 0x8b, 0x00 }, { 0x8c, 0x00 }, { 0x8d, 0x00 },
+        { 0x8e, 0x00 }, { 0x8f, 0x00 },
+        { 0x90, 0x00 }, { 0x91, 0x00 }, { 0x92, 0x00 },
+        { 0x114, 0x80 }, { 0x115, 0x80 },
+    };
+    {
+        // Per resolution (pyopticfilm REGISTER_DPISET, OUTPUT_PIXEL_OFFSET,
+        // DUMMY_BY_DPI, PIXEL_CLOCK_BY_DPI, LPERIOD_BY_DPI; LPERIOD at 1800 dpi
+        // from SilverFast's own 1800 dpi capture, where pyopticfilm has 11490).
+        // The ASIC scans at DPISET * 6: 150 and 300 dpi scan at 600 and are
+        // averaged on the host. The pixel clock goes to 0xa5 and 0xab. The CCD
+        // stagger is set per scan by gl128 calculate_scan_session().
+        struct CustomSensorSettings
+        {
+            ValueFilterAny<unsigned> resolutions;
+            ScanMethod method;
+            unsigned register_dpiset;
+            int output_pixel_offset;
+            int dummy_pixel;
+            int exposure_lperiod;
+            unsigned pixel_clock;
+        };
+
+        CustomSensorSettings custom_settings[] = {
+            { { 150 },  ScanMethod::TRANSPARENCY,  100,  10, 0x01, 11064, 0x02 },
+            { { 300 },  ScanMethod::TRANSPARENCY,  100,  10, 0x01, 11064, 0x02 },
+            { { 600 },  ScanMethod::TRANSPARENCY,  100,  10, 0x01, 11064, 0x02 },
+            { { 720 },  ScanMethod::TRANSPARENCY,  120,  12, 0x01, 11106, 0x02 },
+            { { 900 },  ScanMethod::TRANSPARENCY,  150,  15, 0x01, 11170, 0x02 },
+            { { 1200 }, ScanMethod::TRANSPARENCY,  200,  20, 0x02, 11277, 0x02 },
+            { { 1440 }, ScanMethod::TRANSPARENCY,  240,  24, 0x02, 11362, 0x02 },
+            { { 1800 }, ScanMethod::TRANSPARENCY,  300,  30, 0x02, 11206, 0x02 },
+            { { 2400 }, ScanMethod::TRANSPARENCY,  400,  40, 0x03, 11703, 0x01 },
+            { { 3600 }, ScanMethod::TRANSPARENCY,  600,  60, 0x04, 13407, 0x01 },
+            { { 7200 }, ScanMethod::TRANSPARENCY, 1200, 120, 0x17, 15963, 0x01 },
+        };
+
+        const auto common_regs = sensor.custom_regs;
+        for (const CustomSensorSettings& setting : custom_settings) {
+            sensor.resolutions = setting.resolutions;
+            sensor.method = setting.method;
+            sensor.shading_resolution = setting.resolutions.values()[0];
+            sensor.register_dpiset = setting.register_dpiset;
+            sensor.output_pixel_offset = setting.output_pixel_offset;
+            sensor.dummy_pixel = setting.dummy_pixel;
+            sensor.exposure_lperiod = setting.exposure_lperiod;
+            sensor.custom_regs = common_regs;
+            sensor.custom_regs.set_value(0xa5, setting.pixel_clock);
+            sensor.custom_regs.set_value(0xab, setting.pixel_clock);
+            s_sensors->push_back(sensor);
+        }
+    }
+
+
     sensor = Genesys_Sensor();
     sensor.sensor_id = SensorId::CCD_IMG101; // gl846
     sensor.resolutions = { 75, 100, 150, 300, 600, 1200 };
diff --git a/doc/descriptions/genesys.desc b/doc/descriptions/genesys.desc
index 43b0736..4f2f805 100644
--- a/doc/descriptions/genesys.desc
+++ b/doc/descriptions/genesys.desc
@@ -71,11 +71,11 @@
 :status :complete
 :comment "900, 1800, 3600 and 7200 dpi resolutions are supported in both regular transparency and infrared modes"
 
-:model "OpticFilm 8200i"
+:model "OpticFilm 8200i SE"
 :interface "USB"
 :usbid "0x07b3" "0x1825"
-:status :unsupported
-:comment "GL128 based"
+:status :basic
+:comment "GL128 based. 16-bit colour and gray transparency scans at 150-7200 dpi; no infrared yet"
 
 ; -----------------------------------------------------------------------------
 
diff --git a/backend/genesys/gl128.cpp b/backend/genesys/gl128.cpp
index 750c8f2..6cc1508 100644
--- a/backend/genesys/gl128.cpp
+++ b/backend/genesys/gl128.cpp
@@ -1577,7 +1577,10 @@ void CommandSetGl128::asic_boot(Genesys_Device* dev, bool cold) const
     // until power-off.
     dev->interface->write_0x8c(0x10, 0x0c);
     dev->interface->write_0x8c(0x13, 0x0c);
-    static constexpr std::pair<std::uint16_t, std::uint8_t> STARTUP_REGS[] = {
+    // const, not constexpr: libc++ makes this std::pair constructor constexpr
+    // only from C++14, and SANE builds with -std=c++11, so Apple clang rejects
+    // a constexpr array here. Same values, same order.
+    static const std::pair<std::uint16_t, std::uint8_t> STARTUP_REGS[] = {
         { 0x0b, 0x44 }, { 0x13, 0x0f }, { 0x0b, 0x4c },
     };
     for (const auto& r : STARTUP_REGS) {
diff --git a/backend/epson2-io.c b/backend/epson2-io.c
--- a/backend/epson2-io.c
+++ b/backend/epson2-io.c
@@ -20,6 +20,8 @@
 #include "sane/config.h"
 
 #include <ctype.h>
+#include <stdlib.h>
+#include <string.h>
 
 #include "epson2.h"
 #include "epson2-io.h"
@@ -35,12 +37,220 @@
 
 #include "byteorder.h"
 
+#ifdef __APPLE__
+#include <dlfcn.h>
+#endif
+
 /* flaming hack to get USB scanners
  * working without timeouts under linux
  * (cribbed from fujitsu.c)
  */
 unsigned int r_cmd_count = 0;
 unsigned int w_cmd_count = 0;
+
+/*
+ * Epson interpreter (macOS only)
+ *
+ * The Perfection V500 Photo (GT-X770, USB 04b8:0130) does not speak ESC/I on
+ * the USB bus.  Epson's driver reaches it through a closed-source interpreter
+ * that emulates a D2-level ESC/I scanner and drives the scanner's own
+ * protocol.  The interpreter does not open the device itself.  The host hands
+ * it two callbacks that perform one bulk transfer each, and then exchanges
+ * ESC/I bytes with INTWrite and INTRead.
+ *
+ * The library is loaded from the Epson ICA driver installed on the machine,
+ * or from the path in the EPSON2_INTERPRETER environment variable.  It is
+ * not distributed with SANE.  Only one device is supported at a time.
+ */
+
+#ifdef __APPLE__
+
+#define E2I_DEFAULT_PATH \
+	"/Library/Image Capture/Devices/EPSON Scanner.app/Contents/PlugIns/" \
+	"Interpreter 7C.bundle/Contents/MacOS/Interpreter 7C"
+
+/* Slack for INTRead, which can write up to a word past the requested size. */
+#define E2I_READ_SLACK 64
+
+static struct {
+	void *lib;
+	unsigned char (*init) (void *read_cb, void *write_cb, void *refcon);
+	unsigned char (*close) (void);
+	unsigned char (*read) (void *buf, unsigned int size);
+	unsigned char (*write) (void *buf, unsigned int size);
+	SANE_Int dn;		/* sanei_usb handle used by the callbacks */
+	SANE_Bool active;
+	unsigned char *scratch;	/* padded buffer for INTRead */
+	size_t scratch_size;
+} e2i;
+
+/*
+ * USB callbacks for the interpreter: bool cb(buf, size, refcon, aux).  Only
+ * the low byte of the return value counts, so return 1 or 0, never a length.
+ */
+static unsigned char
+e2i_usb_read(void *buf, unsigned int size, void *refcon, void *aux)
+{
+	size_t n = size;
+
+	(void) refcon;
+	(void) aux;
+
+	return sanei_usb_read_bulk(e2i.dn, buf, &n) == SANE_STATUS_GOOD &&
+		n == size;
+}
+
+static unsigned char
+e2i_usb_write(void *buf, unsigned int size, void *refcon, void *aux)
+{
+	size_t n = size;
+
+	(void) refcon;
+	(void) aux;
+
+	return sanei_usb_write_bulk(e2i.dn, buf, &n) == SANE_STATUS_GOOD &&
+		n == size;
+}
+
+SANE_Bool
+e2_interpreter_wanted(SANE_Int dn)
+{
+	SANE_Word vendor = 0, product = 0;
+
+	if (sanei_usb_get_vendor_product(dn, &vendor, &product) !=
+	    SANE_STATUS_GOOD)
+		return SANE_FALSE;
+
+	return vendor == SANE_EPSON_VENDOR_ID && product == 0x0130;
+}
+
+SANE_Bool
+e2_interpreter_active(void)
+{
+	return e2i.active;
+}
+
+SANE_Status
+e2_interpreter_open(SANE_Int dn)
+{
+	const char *path = getenv("EPSON2_INTERPRETER");
+
+	if (path == NULL || *path == '\0')
+		path = E2I_DEFAULT_PATH;
+
+	e2i.lib = dlopen(path, RTLD_NOW);
+	if (e2i.lib == NULL) {
+		DBG(1, "%s: cannot load %s: %s\n", __func__, path, dlerror());
+		DBG(1, "%s: install the Epson ICA driver for this scanner\n",
+		    __func__);
+		return SANE_STATUS_UNSUPPORTED;
+	}
+
+	e2i.init = (unsigned char (*)(void *, void *, void *))
+		dlsym(e2i.lib, "INTInit");
+	e2i.close = (unsigned char (*)(void)) dlsym(e2i.lib, "INTClose");
+	e2i.read = (unsigned char (*)(void *, unsigned int))
+		dlsym(e2i.lib, "INTRead");
+	e2i.write = (unsigned char (*)(void *, unsigned int))
+		dlsym(e2i.lib, "INTWrite");
+
+	if (!e2i.init || !e2i.close || !e2i.read || !e2i.write) {
+		DBG(1, "%s: %s does not export the interpreter interface\n",
+		    __func__, path);
+		dlclose(e2i.lib);
+		memset(&e2i, 0, sizeof(e2i));
+		return SANE_STATUS_UNSUPPORTED;
+	}
+
+	e2i.dn = dn;
+	if (!e2i.init(e2i_usb_read, e2i_usb_write, NULL)) {
+		DBG(1, "%s: the interpreter failed to initialize the scanner\n",
+		    __func__);
+		dlclose(e2i.lib);
+		memset(&e2i, 0, sizeof(e2i));
+		return SANE_STATUS_IO_ERROR;
+	}
+
+	e2i.active = SANE_TRUE;
+	DBG(1, "%s: using %s\n", __func__, path);
+
+	return SANE_STATUS_GOOD;
+}
+
+void
+e2_interpreter_close(void)
+{
+	if (!e2i.active)
+		return;
+
+	e2i.close();
+	dlclose(e2i.lib);
+	free(e2i.scratch);
+	memset(&e2i, 0, sizeof(e2i));
+}
+
+static SANE_Status
+e2i_send(void *buf, size_t buf_size)
+{
+	if (!e2i.write(buf, buf_size))
+		return SANE_STATUS_IO_ERROR;
+
+	return SANE_STATUS_GOOD;
+}
+
+/* Returns the number of bytes copied to buf, 0 on failure. */
+static ssize_t
+e2i_recv(void *buf, ssize_t buf_size)
+{
+	size_t need = (size_t) buf_size + E2I_READ_SLACK;
+
+	if (e2i.scratch_size < need) {
+		unsigned char *p = realloc(e2i.scratch, need);
+
+		if (p == NULL)
+			return 0;
+		e2i.scratch = p;
+		e2i.scratch_size = need;
+	}
+
+	memset(e2i.scratch, 0, need);
+	if (!e2i.read(e2i.scratch, buf_size))
+		return 0;
+
+	memcpy(buf, e2i.scratch, buf_size);
+
+	return buf_size;
+}
+
+#else /* !__APPLE__ */
+
+SANE_Bool
+e2_interpreter_wanted(SANE_Int dn)
+{
+	(void) dn;
+	return SANE_FALSE;
+}
+
+SANE_Bool
+e2_interpreter_active(void)
+{
+	return SANE_FALSE;
+}
+
+SANE_Status
+e2_interpreter_open(SANE_Int dn)
+{
+	(void) dn;
+	return SANE_STATUS_UNSUPPORTED;
+}
+
+void
+e2_interpreter_close(void)
+{
+}
+
+#endif /* __APPLE__ */
+
 
 int
 e2_send(Epson_Scanner * s, void *buf, size_t buf_size, size_t reply_len,
@@ -94,6 +304,13 @@
 
 		return n;
 
+#ifdef __APPLE__
+	} else if (s->hw->connection == SANE_EPSON_USB && e2i.active) {
+		*status = e2i_send(buf, buf_size);
+		w_cmd_count++;
+
+		return *status == SANE_STATUS_GOOD ? buf_size : 0;
+#endif
 	} else if (s->hw->connection == SANE_EPSON_USB) {
 		size_t n;
 		n = buf_size;
@@ -132,6 +349,11 @@
 			else
 				*status = SANE_STATUS_INVAL;
 		}
+#ifdef __APPLE__
+	} else if (s->hw->connection == SANE_EPSON_USB && e2i.active) {
+		if (n)
+			n = e2i_recv(buf, buf_size);
+#endif
 	} else if (s->hw->connection == SANE_EPSON_USB) {
 		/* !!! only report an error if we don't read anything */
 		if (n) {
diff --git a/backend/epson2-io.h b/backend/epson2-io.h
--- a/backend/epson2-io.h
+++ b/backend/epson2-io.h
@@ -23,6 +23,12 @@
 
 
 SANE_Status e2_cmd_simple(Epson_Scanner * s, void *buf, size_t buf_size);
+/* Epson interpreter (macOS only), see epson2-io.c. */
+SANE_Bool e2_interpreter_wanted(SANE_Int dn);
+SANE_Bool e2_interpreter_active(void);
+SANE_Status e2_interpreter_open(SANE_Int dn);
+void e2_interpreter_close(void);
+
 int e2_send(Epson_Scanner * s, void *buf, size_t buf_size,
 		size_t reply_len, SANE_Status * status);
 ssize_t e2_recv(Epson_Scanner * s, void *buf, ssize_t buf_size,
diff --git a/backend/epson2-ops.c b/backend/epson2-ops.c
--- a/backend/epson2-ops.c
+++ b/backend/epson2-ops.c
@@ -668,9 +668,15 @@
 				dev->y_range = &dev->tpu_y_range;
 			}
 
+			/*
+			 * The interpreter of the V500 Photo reports the TPU
+			 * area in units of 1/3200 inch (68.58 x 236.98 mm),
+			 * not in units of the maximum resolution.
+			 */
 			e2_set_tpu_area(s,
 					(es[8] << 8 | es[7]),
 					(es[10] << 8 | es[9]),
+					e2_interpreter_active() ? 3200 :
 					dev->dpi_range.max);
 
 			*source_list_add++ = TPU_STR;
@@ -799,17 +805,20 @@
 	/* add default depth */
 	e2_add_depth(dev, 8);
 
-	if (dev->maxDepth >= 12 || dev->maxDepth == 0) {
+	if (dev->maxDepth >= 12 || dev->maxDepth == 0 ||
+	    e2_interpreter_active()) {
 		if (esci_set_data_format(s, 12) == SANE_STATUS_GOOD)
 			e2_add_depth(dev, 12);
 	}
 
-	if (dev->maxDepth >= 14 || dev->maxDepth == 0) {
+	if (dev->maxDepth >= 14 || dev->maxDepth == 0 ||
+	    e2_interpreter_active()) {
 		if (esci_set_data_format(s, 14) == SANE_STATUS_GOOD)
 			e2_add_depth(dev, 14);
 	}
 
-	if (dev->maxDepth >= 16 || dev->maxDepth == 0) {
+	if (dev->maxDepth >= 16 || dev->maxDepth == 0 ||
+	    e2_interpreter_active()) {
 		if (esci_set_data_format(s, 16) == SANE_STATUS_GOOD)
 			e2_add_depth(dev, 16);
 	}
@@ -864,6 +873,21 @@
 	return status;
 }
 
+
+/*
+ * Resolution in the sub scan (line) direction. The interpreter of the V500
+ * Photo scans infrared at 3200 x 2400 dpi, so the lines of an infrared scan
+ * at 3200 dpi are three quarters as dense as its pixels.
+ */
+static int
+e2_sub_resolution(Epson_Scanner *s)
+{
+	if (e2_interpreter_active() && s->val[OPT_MODE].w == MODE_INFRARED &&
+	    s->val[OPT_RESOLUTION].w == 3200)
+		return 2400;
+
+	return s->val[OPT_RESOLUTION].w;
+}
 
 SANE_Status
 e2_set_extended_scanning_parameters(Epson_Scanner * s)
@@ -880,7 +904,7 @@
 
 	/* ESC R, resolution */
 	htole32a(&buf[0], s->val[OPT_RESOLUTION].w);
-	htole32a(&buf[4], s->val[OPT_RESOLUTION].w);
+	htole32a(&buf[4], e2_sub_resolution(s));
 
 	/* ESC A, scanning area */
 	htole32a(&buf[8], s->left);
@@ -1007,6 +1031,23 @@
 
 	/* ESC t, threshold */
 	buf[33] = s->val[OPT_THRESHOLD].w;
+
+	/*
+	 * The interpreter of the V500 Photo scans infrared with option control
+	 * 3 at 800, 1600 or 3200 (x 2400) dpi, gray, with gamma 3 and no color
+	 * correction.
+	 */
+	if (s->val[OPT_MODE].w == MODE_INFRARED && e2_interpreter_active()) {
+		if (s->val[OPT_RESOLUTION].w != 800 &&
+		    s->val[OPT_RESOLUTION].w != 1600 &&
+		    s->val[OPT_RESOLUTION].w != 3200) {
+			DBG(1, "%s: infrared needs 800, 1600 or 3200 dpi\n",
+			    __func__);
+			return SANE_STATUS_INVAL;
+		}
+		buf[29] = 3;
+		buf[31] = 0;
+	}
 
 	return esci_set_scanning_parameter(s, buf);
 }
@@ -1288,7 +1329,7 @@
 SANE_Status
 e2_init_parameters(Epson_Scanner * s)
 {
-	int dpi, bytes_per_pixel;
+	int dpi, ydpi, bytes_per_pixel;
 	struct mode_param *mparam;
 
 	DBG(5, "%s\n", __func__);
@@ -1296,6 +1337,7 @@
 	memset(&s->params, 0, sizeof(SANE_Parameters));
 
 	dpi = s->val[OPT_RESOLUTION].w;
+	ydpi = e2_sub_resolution(s);
 
 	mparam = &mode_params[s->val[OPT_MODE].w];
 
@@ -1307,14 +1349,14 @@
 		s->val[OPT_RESOLUTION].w) + 0.5;
 
 	s->top = ((SANE_UNFIX(s->val[OPT_TL_Y].w) / MM_PER_INCH) *
-		s->val[OPT_RESOLUTION].w) + 0.5;
+		ydpi) + 0.5;
 
 	s->params.pixels_per_line =
 		((SANE_UNFIX(s->val[OPT_BR_X].w -
 			   s->val[OPT_TL_X].w) / MM_PER_INCH) * dpi) + 0.5;
 	s->params.lines =
 		((SANE_UNFIX(s->val[OPT_BR_Y].w -
-			   s->val[OPT_TL_Y].w) / MM_PER_INCH) * dpi) + 0.5;
+			   s->val[OPT_TL_Y].w) / MM_PER_INCH) * ydpi) + 0.5;
 
 
 	DBG(1, "%s: resolution = %d, preview = %d\n",
@@ -1415,11 +1457,11 @@
 	 * XXX: precalculate the maximum scanning area elsewhere (use dev max_y)
 	 */
 
-	if (SANE_UNFIX(s->val[OPT_BR_Y].w) / MM_PER_INCH * dpi <
+	if (SANE_UNFIX(s->val[OPT_BR_Y].w) / MM_PER_INCH * ydpi <
 	    (s->params.lines + s->top)) {
 		s->params.lines =
 			(SANE_UNFIX(s->val[OPT_BR_Y].w) / MM_PER_INCH *
-			 dpi + 0.5) - s->top;
+			 ydpi + 0.5) - s->top;
 	}
 
 	s->block = SANE_FALSE;
diff --git a/backend/epson2.c b/backend/epson2.c
--- a/backend/epson2.c
+++ b/backend/epson2.c
@@ -365,6 +365,7 @@
 	} else if (s->hw->connection == SANE_EPSON_PIO) {
 		sanei_pio_close(s->fd);
 	} else if (s->hw->connection == SANE_EPSON_USB) {
+		e2_interpreter_close();
 		sanei_usb_close(s->fd);
 	}
 
@@ -492,8 +493,19 @@
 		/* device name has the form pio:0xnnn */
 		status = sanei_pio_open(&s->hw->sane.name[4], &s->fd);
 
-	else if (s->hw->connection == SANE_EPSON_USB)
+	else if (s->hw->connection == SANE_EPSON_USB) {
 		status = sanei_usb_open(s->hw->sane.name, &s->fd);
+
+		/* scanners that need the Epson interpreter (V500 Photo) */
+		if (status == SANE_STATUS_GOOD && e2_interpreter_wanted(s->fd)) {
+			status = e2_interpreter_open(s->fd);
+			if (status != SANE_STATUS_GOOD)
+				sanei_usb_close(s->fd);
+			else
+				/* the interpreter returns infrared as gray */
+				mode_params[MODE_INFRARED].depth = 8;
+		}
+	}
 
 	if (status == SANE_STATUS_ACCESS_DENIED) {
 		DBG(1, "please check that you have permissions on the device.\n");
@@ -978,7 +990,8 @@
 	s->val[OPT_MODE].w = 0;	/* Lineart */
 
 	/* disable infrared on unsupported scanners */
-	if (!e2_model(s, "GT-X800") && !e2_model(s, "GT-X700") && !e2_model(s, "GT-X900") && !e2_model(s, "GT-X980"))
+	if (!e2_model(s, "GT-X800") && !e2_model(s, "GT-X700") && !e2_model(s, "GT-X900") && !e2_model(s, "GT-X980") &&
+	    !e2_model(s, "GT-X770"))
 		mode_list[MODE_INFRARED] = NULL;
 
 	/* bit depth */
@@ -1675,6 +1688,32 @@
 	}
 
 	return SANE_STATUS_GOOD;
+}
+
+/*
+ * The interpreter of the V500 Photo scans infrared at 800, 1600 and 3200 dpi
+ * (3200 x 2400) only. Offer just those resolutions while the infrared mode is
+ * selected.
+ */
+static void
+limit_infrared_resolution(Epson_Scanner *s, SANE_Bool infrared)
+{
+	static SANE_Word infrared_resolution_list[] = { 3, 800, 1600, 3200 };
+
+	if (!e2_interpreter_active())
+		return;
+
+	if (infrared) {
+		s->opt[OPT_RESOLUTION].constraint.word_list =
+			infrared_resolution_list;
+		if (s->val[OPT_RESOLUTION].w != 800 &&
+		    s->val[OPT_RESOLUTION].w != 1600 &&
+		    s->val[OPT_RESOLUTION].w != 3200)
+			s->val[OPT_RESOLUTION].w = 800;
+	} else {
+		s->opt[OPT_RESOLUTION].constraint.word_list =
+			s->hw->resolution_list;
+	}
 }
 
 /*
@@ -1947,6 +1986,7 @@
 		}
 
 		handle_depth_halftone(s, &reload);
+		limit_infrared_resolution(s, optindex == MODE_INFRARED);
 		reload = SANE_TRUE;
 
 		break;
@@ -2110,8 +2150,8 @@
 
 	print_params(s->params);
 
-	/* enable infrared */
-	if (s->val[OPT_MODE].w == MODE_INFRARED)
+	/* enable infrared, the interpreter needs no unlock sequence */
+	if (s->val[OPT_MODE].w == MODE_INFRARED && !e2_interpreter_active())
 		esci_enable_infrared(handle);
 
 	/* ESC , bay */
diff --git a/backend/epson2_usb.c b/backend/epson2_usb.c
--- a/backend/epson2_usb.c
+++ b/backend/epson2_usb.c
@@ -27,6 +27,7 @@
   0x012a, /* GT-X800, Perfection 4990 PHOTO */
   0x012b, /* ES-H300, GT-2500 */
   0x012c, /* GT-X900, Perfection V700 Photo, Perfection V750 Photo */
+  0x0130, /* GT-X770, Perfection V500 Photo (needs the Epson interpreter) */
   0x0135, /* GT-X970 */
   0x0138, /* ES-H7200, GT-20000 */
   0x014b, /* ES-G11000, Expression 11000XL */

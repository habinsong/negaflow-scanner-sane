class SaneBackendsNegaflow < Formula
  desc "SANE scanner backends with Coolscan depth-list, epson2 scan-height and infrared fixes"
  homepage "https://www.sane-project.org/"
  url "https://gitlab.com/-/project/429008/uploads/843c156420e211859e974f78f64c3ea3/sane-backends-1.4.0.tar.gz"
  version "1.4.0-negaflow.3"
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

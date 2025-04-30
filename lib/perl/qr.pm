package qr;

use strict; use warnings;

use Errno;

my ($n_uid, $n_gid, $shm_dir);
BEGIN {
    $0 = "qrencode";
    %ENV = ();
    umask(0077);
    ($n_uid, $n_gid) = ($>, $));
    $shm_dir = "/dev/shm/qrencode";
    mkdir($shm_dir)
        or (!$!{ENOENT} and die "Could not create $shm_dir: $!\n");
}

# This class is used from as an nginx perl module, to generate QR codes. This
# is via a POST or GET where the body is a JSON object representing the text to
# be encoded. Then, the qrencode utility is called to generate the QR code. The
# generated QR code is then returned as a PNG image.

use nginx;
use Encode;
use URI;
use URI::QueryParam;
use File::Temp ();
use File::Path ();

my @allowed_fields = qw(
    text size level margin color bgcolor type dpi micro kanji eightbit
    ignorecase symversion logo
);

sub generate {
    my ($r) = @_;
    my $resp = eval {handle_qr($r)};
    if($@){
        chomp(my $err = $@);
        logger::error("error: $err");
        return do_err($r, "internal error", 500, $err, "ERR007");
    }
    if($resp == OK){
        logger::info("request handled successfully");
        return OK;
    }
    logger::error("request failed: $resp");
    return do_err($r, "internal error", 500, "request failed", "ERR008");
}

sub handle_qr {
    my ($r) = @_;
    my $method = $r->request_method;
    logger::info("handling $method");

    # fast/simple check
    return do_err($r, "invalid request method", 405, undef, "ERR001")
        if $r->request_method !~ m/^(POST|GET)$/i;

    # body? assume POST/json
    return OK
        if $r->has_request_body(\&handle_qr_post);

    # check query args
    if ($method =~ m/^(GET)$/i and length($r->args // "")) {
        logger::info("handling GET, args: " . $r->args);
        my $req = _post_fields($r->args)
            // return do_err($r, "invalid input", 400, "invalid query args", "ERR002");
        return do_qr($r, $req);
    }

    return do_err($r, "invalid request", 400, "invalid request", "ERR005");
}

sub _post_fields {
    my ($pf) = @_;
    my $u = URI->new();
    $u->query($pf);
    my %req;
    foreach my $k ($u->query_param){
        return if !grep {$_ eq $k} @allowed_fields;
        $req{$k} = $u->query_param($k);
    }
    return \%req;
}

sub handle_qr_post {
    my ($r) = @_;

    # decode body
    my $req;
    eval {
        my $ct = $r->header_in("Content-Type");
        if ($ct =~ m/^application\/json$/i) {
            require JSON;
            $req = JSON::decode_json($r->request_body);
        } elsif ($ct =~ m/^application\/x-www-form-urlencoded$/i) {
            $req = _post_fields($r->request_body)
                // die "invalid form data\n";
        } else {
            die "wrong Content-Type: $ct\n";
        }
        $r->discard_request_body;
    };
    if ($@) {
        chomp(my $err = $@);
        return do_err($r, "invalid input", 400, $err, "ERR006");
    }

    # do QR code generation
    return do_qr($r, $req);
}

sub do_err {
    my ($r, $hdr_err, $status, $err, $error_code) = @_;
    logger::error($err // $hdr_err // "error");
    $r->discard_request_body;
    $r->header_only;
    $r->header_out("X-Error", "$hdr_err (Error Code: $error_code)");
    $r->status($status);
    $r->send_http_header;
    return OK;
}

sub do_qr {
    my ($r, $req) = @_;

    # validate
    logger::info("validating parameters");
    my $err = check_parameters($req);
    if ($err) {
        return do_err($r, "invalid input", 400, "invalid parameters: $err", "ERR004");
    }

    # all is well, generate the QR code
    my $img_data = generate_qr($req);
    if (!length($img_data // "")) {
        return do_err($r, "failed to generate QR code", 500, undef, "ERR003");
    }
    $r->discard_request_body;
    $r->header_out("Content-Type", "image/png");
    $r->header_out("Content-Length", length($img_data));
    $r->status(200);
    $r->send_http_header;
    $r->print($img_data);
    return OK;
}

sub check_parameters {
    my ($req) = @_;

    # Check if text is provided
    if (!length($req->{text} // "")) {
        return "invalid text parameter";
    }

    # Check maximum text size (2953 characters for alphanumeric mode, version 40, level L)
    if (length($req->{text}) > 2953) {
        return "text exceeds maximum allowed size for a QR code";
    }

    # Validate size
    if (length($req->{size} // "")
        and $req->{size} !~ /^\d+$/
        and ($req->{size} < 1 or $req->{size} > 5000)) {
        return "invalid size parameter";
    }

    # Validate level
    if (length($req->{level} // "")
        and $req->{level} !~ /^[LMQH]$/i) {
        return "invalid level parameter";
    }

    # Validate margin
    if (length($req->{margin} // "")
        and $req->{margin} !~ /^\d+$/
        and ($req->{margin} < 0 or $req->{margin} > 200)) {
        return "invalid margin parameter";
    }

    # Validate color
    if (length($req->{color} // "")
        and $req->{color} !~ /^[0-9A-F]{6}$/i) {
        return "invalid color parameter";
    }

    # Validate background color
    if (length($req->{bgcolor} // "")
        and $req->{bgcolor} !~ /^[0-9A-F]{6}$/i) {
        return "invalid bgcolor parameter";
    }

    # Validate type
    if (length($req->{type} // "")
        and $req->{type} !~ /^(PNG|PNG32|EPS|SVG|XPM|ANSI
            |ANSI256|ASCII|ASCIIi|UTF8|UTF8i|ANSIUTF8
            |ANSIUTF8i|ANSI256UTF8)$/ix) {
        return "invalid type parameter";
    }

    # Validate ignorecase
    if (length($req->{ignorecase} // "")
        and $req->{ignorecase} !~ /^(0|1)$/) {
        return "invalid ignorecase parameter";
    }

    # Validate DPI
    if (length($req->{dpi} // "")
        and $req->{dpi} !~ /^\d+$/
        and ($req->{dpi} < 1 or $req->{dpi} > 1200)) {
        return "invalid dpi parameter";
    }

    # Validate micro
    if (length($req->{micro} // "")
        and $req->{micro} !~ /^(0|1)$/) {
        return "invalid micro parameter";
    }

    # Validate kanji
    if (length($req->{kanji} // "")
        and $req->{kanji} !~ /^(0|1)$/) {
        return "invalid kanji parameter";
    }

    # Validate eightbit
    if (length($req->{eightbit} // "")
        and $req->{eightbit} !~ /^(0|1)$/) {
        return "invalid 8bit parameter";
    }

    # Validate symversion
    if (length($req->{symversion} // "")
        and $req->{symversion} !~ /^\d+$/
        and ($req->{symversion} < 1 or $req->{symversion} > 40)) {
        return "invalid symversion parameter";
    }

    # Additional checks for micro QR codes
    if ($req->{micro}) {
        if (defined $req->{level} and $req->{level} eq "H") {
            return "micro and level H are not compatible";
        }
        if (!defined $req->{level}) {
            $req->{level} = "L";
        }
        if (defined $req->{size} and $req->{size} > 10) {
            return "micro and size > 10 are not compatible";
        }
        if (!defined $req->{size}) {
            $req->{size} = 1;
        }
        if (defined $req->{margin} and $req->{margin} > 10) {
            return "micro and margin > 10 are not compatible";
        }
        if (!defined $req->{margin}) {
            $req->{margin} = 0;
        }
        if (defined $req->{symversion} and $req->{symversion} > 4) {
            return "micro and symversion > 4 are not compatible";
        }
        if (!defined $req->{symversion}) {
            $req->{symversion} = 1;
        }
    }

    return;
}

sub generate_qr {
    my ($qr) = @_;
    # we always "print" the to be encoded text to qrencode, so we don't use
    # arguments that need escaping and be possible fork bombs or remote shell
    # execution
    # we also use the ARG version of open so we don't pass through the shell

    # tmp fn suffix
    my $t = time();
    ($::ITERATIONS//=0)++;
    $::ITERATIONS %= 1000;
    my $base_t = "$$.$t.$::ITERATIONS";
    my $suffix = "$base_t.png";
    my $tmp_shm_dir = File::Temp::tempdir(
        "$shm_dir/qrencode-$base_t-XXXXXX",
        DIR => $shm_dir,
    );

    my $img_data;
    eval {
    my $tmp_fn_shm = "$tmp_shm_dir/qrencode-$suffix";
    logger::info("generating QR code $tmp_fn_shm");
    $qr->{level}       //= "H";
    $qr->{size}        //= 10;
    $qr->{margin}      //= 4;
    $qr->{color}       //= "000000";
    $qr->{bgcolor}     //= "FFFFFF";
    $qr->{type}        //= "PNG";
    $qr->{dpi}         //= 72;
    $qr->{micro}       //= 0;
    $qr->{kanji}       //= 0;
    $qr->{eightbit}    //= 0;
    $qr->{ignorecase}  //= 0;
    $qr->{symversion}  //= 4;
    my @qr_cmd = (
        "qrencode",
        "-o", $tmp_fn_shm,
        $qr->{size}       ? ("-s", $qr->{size}):(),
        $qr->{level}      ? ("-l", $qr->{level}):(),
        $qr->{margin}     ? ("-m", $qr->{margin}):(),
        $qr->{color}      ? ("--foreground", $qr->{color}):(),
        $qr->{bgcolor}    ? ("--background", $qr->{bgcolor}):(),
        $qr->{type}       ? ("-t", $qr->{type}):(),
        $qr->{dpi}        ? ("-d", $qr->{dpi}):(),
        $qr->{micro}      ? ("-M", $qr->{micro}):(),
        $qr->{kanji}      ? ("-k", $qr->{kanji}):(),
        $qr->{eightbit}   ? ("-8", $qr->{eightbit}):(),
        $qr->{ignorecase} ? ("-i", $qr->{ignorecase}):(),
        $qr->{symversion} ? ("-v", $qr->{symversion}):(),
    );
    logger::info("qrencode command: ".join(" ", @qr_cmd));
    open(my $fh, "|-", @qr_cmd)
        or die "Could not open qrencode: $!\n";
    binmode($fh);
    Encode::_utf8_off($qr->{text});
    print {$fh} $qr->{text};
    if(!close($fh)){
        my $err = $!;
        if($?){
            my $exit_c = $? >> 8;
            my $signal = $? & 127;
            logger::error("qrencode failed: exit code: $exit_c, signal: $signal".($err?" ($err)":""));
            return;
        } else {
            logger::error("qrencode failed: $err");
            return;
        }
    }

    # Add logo if enabled
    if($qr->{logo}){
        my $logo_fn = "/app/site/logo.png";
        if(-s $logo_fn){
            logger::info("adding logo with file: $logo_fn");

            # Calculate the effective size of the QR code (size + margin)
            # QR code size in modules
            my $qr_size = $qr->{size} * (17 + 4 * $qr->{symversion});
            my $margin_size = $qr->{margin} * $qr->{size};
            my $effective_size = $qr_size + 2 * $margin_size;

            # Resize the logo to fit within the QR code
            # Logo should be 25% of the QR code size
            my $logo_size = int($qr_size * 0.25);
            # Border size matches the pixel size of the QR code
            my $border_size = $qr->{size};

            # Resize the logo
            my $resized_logo_fn = "$tmp_shm_dir/l_r.$suffix";
            system("magick", $logo_fn,
                   "-resize", "${logo_size}x${logo_size}",
                   $resized_logo_fn) == 0
                or die "Could not resize logo: $!\n";

            # Add a white border around the resized logo
            my $bordered_logo_fn = "$tmp_shm_dir/l_b.$suffix";
            system("magick", $resized_logo_fn,
                   "-bordercolor", "white",
                   "-border", "${border_size}x${border_size}",
                   $bordered_logo_fn) == 0
                or die "Could not add border to logo: $!\n";
            unlink($resized_logo_fn)
                or logger::error("Could not delete resized logo: $!");

            # Overlay the bordered logo onto the QR code
            system("magick", $tmp_fn_shm, $bordered_logo_fn,
                   "-compose", "over",
                   "-gravity", "center",
                   "-composite", $tmp_fn_shm) == 0
                or die "Could not overlay logo: $!\n";
            unlink($bordered_logo_fn)
                or logger::error("Could not delete bordered logo: $!");
        } else {
            logger::warn("logo file not found: $logo_fn");
        }
    }

    logger::info("reading QR code $tmp_fn_shm");
    open($fh, "<", $tmp_fn_shm)
        or die "Could not open $tmp_fn_shm: $!\n";
    $img_data = do {local $/; <$fh>};
    close($fh);
    unlink($tmp_fn_shm)
        or logger::error("Could not delete $tmp_fn_shm: $!");

    # cleanup
    File::Path::rmtree($tmp_shm_dir);
    };
    if($@){
        chomp(my $err = $@);
        eval {
            File::Path::rmtree($tmp_shm_dir);
        };
        if($@){
            chomp(my $err2 = $@);
            logger::error("error deleting tmp dir: $err2");
        }
        logger::error("error generating QR code: $err");
        return;
    }
    return $img_data;
}

package logger;

use strict; use warnings;

our $_json_printer;
our $_init_syslog;
our $_syslog_logger;

*fatal = *log_fatal;
*error = *log_error;
*info  = *log_info;
*debug = *log_debug;

sub log_fatal {
    my (@msg) = @_;
    my $msg = do_log("error", @msg);
    die "$msg\n";
}

sub log_error {
    my (@msg) = @_;
    return do_log("error", @msg);
}

sub log_info {
    my (@msg) = @_;
    return do_log("info", @msg);
}

sub log_debug {
    my (@msg) = @_;
    no warnings 'once';
    require Data::Dumper;
    local $Data::Dumper::Sortkeys = 1;
    local $Data::Dumper::Indent   = 0;
    local $Data::Dumper::Terse    = 1;
    local $Data::Dumper::Deepcopy = 1;
    return do_log("debug", map {ref($_)?Data::Dumper::Dumper($_):$_} @msg);
}

sub do_log {
    my ($w, @msg) = @_;
    require POSIX;
    require Time::HiRes;
    local $::LOG_PREFIX = $::LOG_PREFIX // "";
    @msg =
        map {split m/\n/, $_//""}
        join("",
        map {defined $_ and ref($_)
            ?do {
                $_ = eval {
                    require JSON;
                    $_json_printer //= JSON->new->canonical->allow_nonref->allow_unknown->allow_blessed->convert_blessed->allow_tags->indent(0);
                    $_json_printer->encode($_);
                };
                $_//"";
            }
            :$_//""
        } @msg);
    my ($tm, $usec) = Time::HiRes::gettimeofday();
    $usec = sprintf("%06d", $usec);
    my @tm = localtime($tm);
    my $msg = join("\n", map {POSIX::strftime("%H:%M:%S.$usec", @tm)." [$$] [$w]: $::LOG_PREFIX$_"} map {split m/\n/, $_//""} @msg);
    print STDERR "$msg\n";
    return;
}

1;

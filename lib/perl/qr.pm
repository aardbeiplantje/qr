package qr;

use strict; use warnings;

# This class is used from as an nginx perl module, to generate QR codes. This
# is via a POST or GET where the body is a JSON object representing the text to
# be encoded. Then, the qrencode utility is called to generate the QR code. The
# generated QR code is then returned as a PNG image.

use nginx;
use Encode;
use JSON;
use URI;
use URI::QueryParam;

sub generate {
    my ($r) = @_;
    my $resp = eval {handle_qr($r)};
    if($@){
        chomp(my $err = $@);
        logger::error("error: $err");
        return HTTP_BAD_REQUEST;
    }
    return $resp;
}

sub handle_qr {
    my ($r) = @_;
    my $method = $r->request_method;
    logger::info("handling $method");

    # fast/simple check
    return HTTP_BAD_REQUEST
        if $r->request_method !~ m/^(POST|GET)$/i;

    # body? assume POST/json
    return OK
        if $r->has_request_body(\&handle_qr_post);

    # check query args
    if($method =~ m/^(GET)$/i and length($r->args//"")){
        logger::info("handling GET, args: ".$r->args);
        my $u = URI->new();
        $u->query($r->args);
        my %req;
        foreach my $k ($u->query_param){
            $req{$k} = $u->query_param($k);
        }
        return do_qr($r, \%req);
    }

    return HTTP_BAD_REQUEST;
}

sub handle_qr_post {
    my ($r) = @_;

    # decode body
    my $req;
    eval {
        my $ct = $r->header_in("Content-Type");
        die "wrong Content-Type: $ct\n"
            if $ct !~ m/^application\/json/i;
        $req = decode_json($r->request_body);
        $r->discard_request_body;
    };
    if($@){
        chomp(my $err = $@);
        logger::error("error decoding json: $err");
        $r->header_only;
        $r->header_out("Content-Length", 0);
        $r->header_out("Connection", "close");
        $r->header_out("X-Error", "Invalid input");
        $r->status(400);
        $r->send_http_header;
        return OK;
    }

    # do QR code generation
    return do_qr($r, $req);
}

sub do_qr {
    my ($r, $req) = @_;

    # validate
    logger::info("validating");
    my $err = check_parameters($req);
    if($err){
        logger::error("invalid parameters: $err");
        $r->header_only;
        $r->header_out("Content-Length", 0);
        $r->header_out("Connection", "close");
        $r->header_out("X-Error", "Invalid input");
        $r->status(400);
        $r->send_http_header;
        return OK;
    }

    # all is well, generate the QR code
    logger::info("generating QR code");
    my $img_data = generate_qr($req);
    if(!length($img_data//"")){
        logger::error("failed to generate QR code");
        $r->header_only;
        $r->header_out("Content-Length", 0);
        $r->header_out("Connection", "close");
        $r->header_out("X-Error", "Failed");
        $r->status(500);
        $r->send_http_header;
        return OK;
    }
    $r->header_out("Content-Type", "image/png");
    $r->header_out("Content-Length", length($img_data));
    $r->status(200);
    $r->send_http_header;
    $r->print($img_data);
    return OK;
}

sub check_parameters {
    my ($req) = @_;
    if(!length($req->{text}//"")){
        return "invalid text parameter";
    }
    if(length($req->{size}//"")
        and $req->{size} !~ /^\d+$/){
        return "invalid size parameter";
    }
    if(length($req->{level}//"")
        and $req->{level} !~ /^[LMQH]$/i){
        return "invalid level parameter";
    }
    if(length($req->{margin}//"")
        and $req->{margin} !~ /^\d+$/){
        return "invalid margin parameter";
    }
    if(length($req->{color}//"")
        and $req->{color} !~ /^[0-9A-F]{6}$/i){
        return "invalid color parameter";
    }
    if(length($req->{bgcolor}//"")
        and $req->{bgcolor} !~ /^[0-9A-F]{6}$/i){
        return "invalid bgcolor parameter";
    }
    if(length($req->{type}//"")
        and $req->{type} !~ /^(PNG|PNG32|EPS|SVG|XPM|ANSI
            |ANSI256|ASCII|ASCIIi|UTF8|UTF8i|ANSIUTF8
            |ANSIUTF8i|ANSI256UTF8)$/ix){
        return "invalid type parameter";
    }
    if(length($req->{ignorecase}//"")
        and $req->{ignorecase} !~ /^(0|1)$/){
        return "invalid ignorecase parameter";
    }
    if(length($req->{dpi}//"")
        and $req->{dpi} !~ /^\d+$/){
        return "invalid dpi parameter";
    }
    if(length($req->{micro}//"")
        and $req->{micro} !~ /^(0|1)$/){
        return "invalid micro parameter";
    }
    if(length($req->{kanji}//"")
        and $req->{kanji} !~ /^(0|1)$/){
        return "invalid kanji parameter";
    }
    if(length($req->{eightbit}//"")
        and $req->{eightbit} !~ /^(0|1)$/){
        die "invalid 8bit parameter";
    }

    return;
}

sub generate_qr {
    my ($json_body) = @_;
    # we always "print" the to be encoded text to qrencode, so we don't use
    # arguments that need escaping and be possible fork bombs or remote shell
    # execution
    # we also use the ARG version of open so we don't pass through the shell
    my $t = time();
    ($::ITERATIONS//=0)++;
    my $tmp_fn_shm = "/dev/shm/qrencode-$$.$t.$::ITERATIONS.out";
    open(my $fh, "|-", "qrencode",
            "-o", $tmp_fn_shm,
            $json_body->{size}
                ? ("-s", $json_body->{size}):(),
            $json_body->{level}
                ? ("-l", $json_body->{level}):(),
            $json_body->{margin}
                ? ("-m", $json_body->{margin}):(),
            $json_body->{color}
                ? ("-c", $json_body->{color}):(),
            $json_body->{bgcolor}
                ? ("-b", $json_body->{bgcolor}):(),
            $json_body->{type}
                ? ("-t", $json_body->{type}):(),
            $json_body->{dpi}
                ? ("-d", $json_body->{dpi}):(),
            $json_body->{micro}
                ? ("-M", $json_body->{micro}):(),
            $json_body->{kanji}
                ? ("-k", $json_body->{kanji}):(),
            $json_body->{eightbit}
                ? ("-8", $json_body->{eightbit}):(),
            $json_body->{ignorecase}
                ? ("-i", $json_body->{ignorecase}):()
        )
        or die "Could not open qrencode: $!";
    binmode($fh);
    Encode::_utf8_off($json_body->{text});
    print {$fh} $json_body->{text};
    if(!close($fh)){
        my $err = $!;
        if($?){
            my $exit_c = $? >> 8;
            my $signal = $? & 127;
            logger::error("qrencode failed: $err, exit code: $exit_c, signal: $signal");
        } else {
            logger::error("qrencode failed: $err");
        }
    }

    # read the generated file
    open($fh, "<", $tmp_fn_shm)
        or die "Could not open $tmp_fn_shm: $!";
    my $img_data = do {local $/; <$fh>};
    close($fh);
    unlink($tmp_fn_shm);
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

1;

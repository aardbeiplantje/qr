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
    print STDERR "generate\n";
    my $resp = eval {handle_qr($r)};
    if($@){
        chomp(my $err = $@);
        print STDERR "Error: $err\n";
        return HTTP_BAD_REQUEST;
    }
    return $resp;
}

sub handle_qr {
    my ($r) = @_;
    my $method = $r->request_method;
    print STDERR "handling $method\n";

    # fast/simple check
    return HTTP_BAD_REQUEST
        if $r->request_method !~ m/^(POST|GET)$/i;

    # body? assume POST/json
    return OK
        if $r->has_request_body(\&handle_qr_post);

    # check query args
    if($method =~ m/^(GET)$/i and length($r->args//"")){
        print STDERR "args: ", $r->args, "\n";
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
        print STDERR "invalid JSON: $@\n";
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
    print STDERR "validating\n";
    my $err = check_parameters($req);
    if($err){
        print STDERR "invalid parameters: $err\n";
        $r->header_only;
        $r->header_out("Content-Length", 0);
        $r->header_out("Connection", "close");
        $r->header_out("X-Error", "Invalid input");
        $r->status(400);
        $r->send_http_header;
        return OK;
    }

    # all is well, generate the QR code
    print STDERR "generating\n";
    my $img_data = generate_qr($req);
    if(!length($img_data//"")){
        print STDERR "qrencode failed\n";
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
            print STDERR "qrencode failed: $exit_c, $signal, $err\n";
        } else {
            print STDERR "qrencode failed: $err\n";
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

1;

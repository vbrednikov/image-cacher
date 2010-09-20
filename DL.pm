#!/usr/bin/perl -wT
#use LWP::UserAgent;
use IO::Socket::INET;
use IO::Select;
use Image::Size qw/imgsize/;
use File::Temp qw/tempfile/;

use strict;
package DL;

sub new {
    my $class=shift;
    my $self={};
    bless ($self,$class);
    $self->init();
    return $self;
}

sub init {
    my $self=shift;
    $self->{max_size}=102400;   # maximum download length (without headers)
    $self->{buf_size}=1024;     # socket buffer size
    $self->{max_dimension}=600; # maximum image width or height (pixels)
    $self->{temp_path}='/tmp';       # temp folder, must be placed in the same fs as cache
}

sub _error {
    my $self=shift;
    my $str=shift;
    $self->{error_msg}=$str;
    return;
}

sub error {
    my $self=shift;
    return $self->{error_msg};
}

#sub temp {
#    my $self=shift;
#    my $temp_path=shift;
#    if(!-d $temp_path && !mkdir($temp_path)){
#        return $self->_error("Temp dir doesn't exist and could not be created");
#    }
#    $self->{temp_path}=$temp_path;
#    1;
#}

sub cache {
    my $self=shift;
    if (@_){$self->{cache}=shift}
    $self->{temp_path}=$self->{cache}->temp();
    return $self->{cache};
}

#sub lwp_get {
#    my ($self,$url,undef)=@_;
#    print "Getting $url\n";
#    my $req=HTTP::Request->new('GET' => $url);
#    my $res=$self->{UA}->request($req);
#    if($res->is_success()){
#        print "done\n";
#        open(F,">/tmp/file");
#        print F $res->content;
#        close F;
#    }
#    else
#    {
#        print "Error getting $url\n";
#    }
#}

sub parse_uri {
    my $self=shift;
    my $uri=shift or return;

    $uri =~s/([&;`'\\"|*?~<>^()\[\]{}\$])/\\$1/g;
    $uri =~ s|^(\w+)://||;
    my $scheme = $1;
    my ($host,$path);
    if($scheme eq 'http'){
        ($host,$path) = $uri =~ m|([-_a-z0-9.]+)(/?.*)$|si;
    }
    unless ($path) { $path="/" }
    return ($host,$path)
}

#sub jpegsize {
## copypaste with some changes from Image::Size::jpegsize
#    my $self=shift;
#    my $str=shift or return;
#    my $MARKER = chr 0xff; # Section marker
#
#    my $SIZE_FIRST = 0xC0;   # Range of segment identifier codes
#    my $SIZE_LAST  = 0xC3;   #  that hold size info.
#
#    my ($x, $y, $id) = (undef, undef, 'Could not determine JPEG size');
#
#    my ($marker, $code, $length);
#    my $segheader;
#
#    # Dummy read to skip header ID
#    read($stream,undef,2);
#    while (1)
#    {
#        $length = 4;
#        my $res=read($stream,$segheader,$length);
#        if(! defined $res || $res == 0){
#            # end of current stream, remember bytes
#        }
#
#        # Extract the segment header.
#        ($marker, $code, $length) = unpack 'a a n', $segheader;
#
#        # Verify that it's a valid segment.
#        if ($marker ne $MARKER)
#        {
#            # Was it there?
#            $id = 'JPEG marker not found';
#            last;
#        }
#        elsif ((ord($code) >= $SIZE_FIRST) && (ord($code) <= $SIZE_LAST))
#        {
#            # Segments that contain size info
#            $length = 5;
#            my $buf='';
#            read($stream,$buf,$length);
#            ($y, $x) = unpack 'xnn', $buf;
#            $id = 'JPG';
#            last;
#        }
#        else
#        {
#            # Dummy read to skip over data
#            read($stream,undef,($length - 2));
#        }
#    }
#
#    return ($x, $y, $id);
#}

sub parse_headers {
    my $self=shift;
    my $headers_raw=shift;

    my $headers={};
    my $code=undef;
    if($headers_raw=~s/HTTP\/1.1 (\d+) [a-z0-9 ]+\r\n//gmsi){
        $code=$1;
    } else {
        return $self->_error("Can't get HTTP response");
    }
    %{$headers}=( map { chomp; $1 => $2 if /^([^:]+?): (.*)$/ } split(/\r\n/,$headers_raw));
    $headers->{code}=$code;
    return $headers;
}


sub get {
    my $self=shift;
    my $uri=shift or return;

    my ($host,$path)=$self->parse_uri($uri) or return $self->_error("Could not parse $uri");

    my $socket=IO::Socket::INET->new(
        PeerAddr => $host,
        PeerPort => 80,
        Proto    => "tcp"
    ) or return $self->_error("Can't open socket to $host: $!\n");
#    $socket->autoflush(1);
    $socket->send("GET $path HTTP/1.1\r\n");
    $socket->send("Host: $host\r\n");
    $socket->send("Accept: */*\r\n");
    $socket->send("User-Agent: Wget/1.12 (linux-gnu)\r\n");
    $socket->send("Connection: close\r\n");
    $socket->send("\r\n");

    my $normal=0;
    my $first=1;
    my $out_headers='';
    my $dl_size=0;
    my $headers;
    my $size_known=0;
    my $fh=undef;

    my $select=IO::Select->new($socket);

    while($select->can_read(60)){
        my $response='';
        my $buf=$self->{buf_size};
        my $bytes_left=$self->{max_size}-$dl_size;
        if($bytes_left < 0){
            return $self->_error("Size limit exceeded. Downloaded $dl_size, max is $self->{max_size}");
            $socket->close();
            $select->remove($socket);
        }
        my $ret=$socket->sysread($response,$buf,0);
        if (!defined $ret or $ret == 0) { # error or eof
            if($size_known==0 && $out_headers ne '' && $dl_size > 0){
                print $out_headers."\r\n";
                $fh->seek(0,'SEEK_SET');
                while(<$fh>){print}
            }
            $socket->close(); $select->remove($socket);
            $normal++;
        } else {
            if ($first==1) {
                my ($raw_headers,$content)=$response=~m/^(?:\x0d?\x0a)*(.*)\x0d\x0a\x0d\x0a(.*)$/s; # FIXME: may not be found

                unless($headers=\%{$self->parse_headers($raw_headers)}){
                    return $self->_error("Can't parse headers: ".$self->error());
                }
                unless($headers->{code}){
                    $socket->close(); $select->remove($socket);
                    return $self->_error("Did not get http response");
                } else {
                    unless($headers->{code} eq '200') {    # TODO: follow redirects
                        $socket->close(); $select->remove($socket);
                        if($headers->{code} eq '404') {
                            return $self->_error("Not found");
                        } else {
                            return $self->_error("Expected code 200, got $headers->{code}.");
                        }
                    }
                }

                if($headers->{"Content-Length"}){
                    my $size=$headers->{"Content-Length"};
                    if ($size > $self->{max_size}){
                        $socket->close(); $select->remove($socket);
                        return $self->_error("Size $size is too big (max is $self->{max_size})");
                    }
                    $size_known=1;
                }

                if($headers->{"Content-Type"}) {
                    my $content_type=$headers->{"Content-Type"};
                    if($content_type=~m/^image\//){
                       if ( $content_type ne 'image/jpeg' && $content_type ne 'image/jpg'){
                            my ($x,$y,$id);
                            unless (($x,$y,$id)=Image::Size::imgsize(\$content)){
                                warn "Unable to determine image type\n";
                            } else {
#                                 warn "$x,$y,$id\n";
                                if ( (($x>$y)?$x:$y) > $self->{max_dimension} ) {
                                    $socket->close(); $select->remove($socket);
                                    return $self->_error("Image is too large: $x"."x$y");
                                }
                            }
                        } else { # TODO: get jpeg dimensions
                        }
                    } else { #not image
                        $socket->close(); $select->remove($socket);
                        return $self->_error("URI $uri is not image (content type returned: $content_type)");
                    }
                } else {
                    $socket->close(); $select->remove($socket);
                    return $self->_error("URI $uri is not image (content type returned: ".$headers->{"Content-Type"}.")");
                }
                while(my ($k,$v)=each %{$headers}){
#                    if ($k ne 'code' && $k ne 'Location'){
                        $out_headers.="$k: $v\r\n";
#                    }
                }

                $fh=$self->{cache}->tmpfile();  # File::Temp object
                binmode($fh);
                if($size_known){
                    binmode(STDOUT);
                    print $out_headers;
                    print "\r\n$content";
                }
                $dl_size+=length($content);
                print $fh $content;
                $first = 0;
            } else {
                $dl_size+=length($response);
                print $response if $size_known;
                print $fh $response;
            }

        }
    }
    my $ret={
        URI => $uri,
        filename => $fh->filename,
        date => time(),
        headers => $headers
    };

    # TODO: close all sockets
    close $fh;
    return $ret;
#    return $fh->filename()."\n";
1;   
}


1;

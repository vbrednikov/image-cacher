#!/usr/bin/perl -wT
use File::Path;
use File::Temp;
use Cwd;
use Digest::MD5;
use Data::Dumper;

use strict;

package Cache;

sub new {
    my $class=shift;
    my $self={};
    bless ($self,$class);
    my $p=shift;
    return $self;
}

sub init {
    my $self=shift;
    $self->{path}='';
    $self->{errormsg}='';
}


=head 2 $c->error()

Returns last encountered error as a string

=cut

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

=head 2 $c->path($path)

Set cache root. Create if not exists.
=cut
sub path {
    my $self=shift;
    my $path=shift or return;
    unless(-d $path){
       unless( $self->create_folder($path)) {
           return $self->_error( "Can't create folder $path: ".  $self->error());
       }
    }
    if (! -w $path) { return $self->_error("$path is not writable"); }

    foreach my $dir (qw/cache info tmp/){
        unless (-d "$path/$dir"){
            $self->create_folder("$path/$dir") || return $self->_error("Can't create folder $path/$dir: ".  $self->error());
        }
    }
    $self->{path}=Cwd::abs_path($path);
}

sub tmpfile {
    my $self=shift;
    return new File::Temp(DIR=>$self->{path}."/tmp",UNLINK=>0);
}

sub create_folder {
    my $self=shift;
    my $dir=shift || return;

    my @dirs   = ();
    my @path   = split /\//, $dir;
    foreach my $c(@path){
        push @dirs, $c;
        my $current=join('/',@dirs);
        if(!-d $current) {
            mkdir $current, 0755 || return $self->_error("Can't create parent component $current for $dir: $!");
        }
    }
    1;
}

sub temp {
    my $self=shift;
    return $self->{path}."/tmp";
}


sub clean {
    my $self=shift;
    if(-d $self->{path}){
        File::Path::remove_tree($self->{path},{error=>\my $errs});
        if(@$errs){
            for my $diag (@$errs){
                my ($file,$message)=%$diag;
                if ($file eq ''){return $self->_error("General error while removing $self->{path}: $message")}
                else {return $self->_error( "Can't remove $file: $message")}
            }
        }
    }
    $self->path($self->{path});

}
=head2 $c->get_filename()

Get internal filename for URI

=cut
sub get_filename {
    my $self=shift;
    my $name=shift;
    my $md5=Digest::MD5::md5_hex($name);
    my ($f1,$f2)=$md5=~m/^.*(..)(.)$/;
    return ["$f2/$f1",$md5];
    
}

=head2 $c->store( PARAMS )
$c->store(
    URI => "http://www.google.com/images/logos/ps_logo2.png",
    filename => "/path/to/file",
    last_modified => 123456789
    content_type => "text/html"
);
=cut
sub store {
    my $self=shift;
    my %args=( @_ );
    if (!exists $args{URI} || !exists $args{filename} ) {
        my ($package,$caller)=(caller(0))[0,3];
        return $self->error("Incorrect syntax for $package"."::"."$caller. URI and filename are required");
    }

    -f $args{filename} || return $self->_error("$args{filename} doesn't exist");
    my ($folder,$file)=@{$self->get_filename($args{URI})};
    foreach my $t(qw/cache info/) {
        $self->create_folder("$self->{path}/$t/$folder") || 
            return $self->_error("Can't create folder $t/$folder: ". $self->error());
    }
    rename $args{'filename'}, $self->{path}."/cache/$folder/$file" ||
        return $self->_error("Can't rename ".$args{'filename'}." to ".$self->{path}."/cache/$folder/$file: $!");

    open(DATA,">$self->{path}/info/$folder/$file") || return $self->_error("Can't open $self->{path}/info/$folder/$file: $!");
    print DATA Data::Dumper::Dumper(\%args) || return $self->_error("Can't write to $self->{path}/info/$folder/$file: $!");
    close DATA;


    return $self->{path}."/cache/$folder/$file";
        
}

sub lookup {
    my $self=shift;
    my $uri=shift;
    my ($folder,$file)=@{$self->get_filename($uri)};
    if(-f "$self->{path}/cache/$folder/$file" && -f "$self->{path}/info/$folder/$file"){
        open(INFO,"<$self->{path}/info/$folder/$file") || return $self->_error("Can't open info file for $uri: $!");
        my $tmp=$/;
        undef $/;
        my $data=<INFO>;
        $/=$tmp;
        close(INFO);

        my $VAR1;  # something awful
        eval($data);
        $VAR1->{filepath}="$self->{path}/cache/$folder/$file";
        return \$VAR1;
    } else {
        return;
    }
}

sub get {
    my $self=shift;
    my $uri=shift;
    my $info=$self->lookup($uri);
    unless($info) {
        return $self->_error("$uri not found");
    } else {
        open(IN,"<".${$info}->{filepath}) || return $self->error("Can't open ".${$info}->{filepath}.": $!");
#        print Data::Dumper::Dumper(\$info);
        print "HTTP/1.1 ${$info}->{headers}->{code} OK\r\n";
        while(my ($k,$v)= each %{${$info}->{headers}}){
            if($k ne 'code'){
                print "$k: $v\r\n";
            }
        }
        print "\r\n";
        binmode(IN);
        binmode(STDOUT);
        while(1){
            my ($res,$buf);
            $res=read(IN,$buf,1024);
            if(!$res || $res == 0){
                last;
            }
            print $buf;
        }
        close IN;
        1;
    }
}
        
1

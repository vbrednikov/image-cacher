#!/usr/bin/perl -w

use FCGI;
use Show;
use strict;
use warnings;

#use POSIX;
#fork_proc() && exit 0;
#POSIX::setsid() or die "Can't set sid: $!\n";
#chdir '/' or die "Can't chdir to /: $!\n";
#POSIX::setuid(65534) or die "Can't setuid 65534: $!\n";
#reopen_std();

my $count=0;
my $socket=FCGI::OpenSocket(":9000",5);
my $request=FCGI::Request(\*STDIN,\*STDOUT,\*STDERR,\%ENV, $socket);


while($request->Accept() >= 0) {
    my $view=new Show();
    unless($view->run()){
        print "Content-type: text/html\r\n\r\n";
        print $view->error();
    }
}

sub fork_proc {
    my $pid;
    FORK: {
        if (defined ($pid = fork)) {
            return $pid;
        }
        elsif ($!=~/No more process/){
            sleep 5;
            redo FORK;
        }
        else {
            die "Can't fork: $!\n";
        }
    }
}

sub reopen_std {
    open(STDIN,  "+>/dev/null") or die "Can't open STDIN: $!";
    open(STDOUT, "+>&STDIN") or die "Can't open STDOUT: $!";
    open(STDERR, "+>&STDIN") or die "Can't open STDERR: $!";
};


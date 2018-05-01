#use feature 'signatures';
#no warnings "experimental::signatures";
use strict;

my $GNUPLOT = "gnuplot";
my $PDFLATEX = "pdflatex";
my $BIBTEX = "bibtex";
my $OPEN = "open -a /Applications/Skim.app";

use IPC::Open2;

my $cmd = shift @ARGV;

if ($cmd eq "render_latex") {
  my $filename = shift @ARGV;
  my $instring = shift @ARGV;
  render_latex($filename, $instring);

} elsif ($cmd eq "render_gnuplot") {
  my $filename = shift @ARGV;
  render_gnuplot($filename);

} elsif ($cmd eq "watch") {

  my $makestring = shift @ARGV;
  my @files = @ARGV;

  watch($makestring, @files);

} elsif ($cmd eq "watch_gnuplot_piped") {
  my $cmd = shift @ARGV;
  my $pipestring = shift @ARGV;
  my @files = @ARGV;

  watch_gnuplot_piped($cmd, $pipestring, @files);

} else {
  die "unknown input";
}

sub cmd_read { # ($cmd, $waitfor) {
  my ($cmd, $waitfor) = @_;

  my ($out, $in);
  my $pid = open2($out, $in, $cmd);

  my $ret = "";

  local $/ = $waitfor;
  while (my $temp = <$out>) {
    $ret .= $temp;
    if ($waitfor eq ".") {
      print $temp;
    } else {
      print ".";
    }
    flush stdout;
  }

  close($out);
  close($in);

  waitpid($pid, 0);
  my $status = $? >> 8;

  if ($waitfor eq ".") {
  } else {
    print "\n";
  }

  return ($status, $ret);
}

sub watch { #($makestring, @files) {
  my ($makestring, @files) = @_;

  my $do = "make $makestring";
  print "watching $makestring\n";
  my $stats = {};
  my $delay = 1;

  while (1) {
    my $has_changed = 0;
    for my $file (@files) {
      my $mtime = (stat($file))[9];
      if ($stats->{$file} != $mtime) {
        if (! $has_changed) {
          print "$file changed\n";
        }
        $has_changed = 1;
      }
      $stats->{$file} = $mtime;
    }
    if ($has_changed) {
      #print "$do";
      my ($status, $lines) = cmd_read($do, ".");

      if ($status) {
        print "HAD ERROR\n";
      } else {
        print "done\n";
      }
      $has_changed = 0;
    }

    sleep($delay);
  }
}

sub render_gnuplot { #($filename) {
  my ($filename) = @_;
  my $do = "$GNUPLOT \"$filename\"";
  print "  gnuplot\n";
  my ($status, $out) = cmd_read($do, \1024);
}

sub render_latex { #($filename, $instring) {
  my ($filename, $instring) = @_;
  my $run_bibtex = 1;
  my $run_latex = 1;

  my $first = 1;

  my $count = 0;

  my @last_warns;

  while ($run_latex) {
    $run_latex = 0;
    my $do = "$PDFLATEX -synctex=1 -interaction nonstopmode \"$instring\"";

    print "  pdflatex";
    my ($status, $out) = cmd_read($do, \1024);
    $count += 1;

    my @lwarns = ($out =~ m/LaTeX Warning: ([^.]*?\.)/gm);
    my @undefs = ($out =~ m/! Undefined control sequence.\nl.([0-9]+) (.*?)\n/g);

    if (@undefs) {
      while (@undefs) {
        my $line = shift @undefs;
        my $cmd  = shift @undefs;
        print "  ERROR: undefined command $cmd on line $line\n";
      }
      exit(1);
    }

    my @others = ($out =~ m/^! (.*?)$/gm);
    if (@others) {
      foreach my $error (@others) {
        print "  ERROR: $error\n";
      }
      exit(1);
    }

    @last_warns = @lwarns;

    if ($out =~ m/Rerun to get cross-references right/ or
        $out =~ m/Rerun to get citations correct/) {
      #print "need to rerun latex\n";
      $run_latex = 1;
    }
    if ($out =~ m/There were undefined references/ or
        $out =~ m/There were undefined citations/) {
      #print "need to run bibtex\n";
      if ($count <= 1) {
        $run_bibtex = 1;
      }
    }
    if ($run_bibtex) {
      $run_latex = 1;
      my $do = "$BIBTEX $filename";
      print "  bibtex";
      my ($status, $out) = cmd_read($do, \1024);
      #print "$out\n";
      $run_bibtex = 0;
    }

    if ($count > 3 or ! $run_latex) {
      foreach my $warn (@lwarns) {
        print "  LaTeX Warning: $warn\n";
      }
    }
    if ($count > 3) {
      print "  COULD NOT FULLY COMPLETE RENDERING PROCESS, PERHAPS MISSING CITATIONS?\n";
      exit 0;
    }
  }
}

sub watch_gnuplot_piped { #($cmd, $pipestring, @files) {
  my ($cmd, $pipestring, @files) = @_;

  print "watching $cmd, piping '$pipestring'\n";

  my $stats = {};
  my $delay = 1;

  my ($out, $in);
  my $pid = open2($out, $in, $cmd);
  $out->blocking(0);
  $in->autoflush();

  print read_pipe($out);

  while (1) {
    my $has_changed = 0;
    for my $file (@files) {
      my $mtime = (stat($file))[9];
      if ($stats->{$file} != $mtime) {
        if (! $has_changed) {
          print "$file changed\n";
        }
        $has_changed = 1;
      }
      $stats->{$file} = $mtime;
    }
    if ($has_changed) {
      print $in $pipestring . "\n";
      print read_pipe($out);

      $has_changed = 0;
    }
    sleep($delay);
  }
}

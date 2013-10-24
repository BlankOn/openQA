package openqa;
use strict;
require 5.002;

require Exporter;
our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);
$VERSION = sprintf "%d.%03d", q$Revision: 1.12 $ =~ /(\d+)/g;
@ISA = qw(Exporter);
@EXPORT = qw(
$prj $basedir $perldir $perlurl $resultdir $scheduledir $app_title $app_subtitle @runner $res_css $res_display
$loguploaddir
&parse_log &parse_log_to_stats &parse_log_to_hash &parse_iso &log_to_scriptpath &path_to_url &split_filename &resultname_to_log &resultname_to_url &is_authorized_rw &is_scheduled &get_testimgs &get_waitimgs &get_clickimgs testimg &get_testwavs &running_log &clickimg &path_to_testname &cycle &sortkeys &syntax_highlight &first_run &data_name &parse_refimg_path &parse_refimg_name &back_log &running_state &get_running_modinfo &match_title &needle_info
&test_result &test_result_stats &test_result_hash &test_result_module &test_resultfile_list &testresultdir &test_uploadlog_list
$localstatedir $dbfile
&get_failed_needles
&sanitize_testname
&parse_testname
);
#use lib "/usr/share/openqa/cgi-bin/modules";
use awstandard;
use File::Basename;
use Fcntl;
use JSON "decode_json";
our $basedir=$ENV{'OPENQA_BASEDIR'}||"/var/lib";
our $prj="openqa";
our $perlurl="$prj/perl/autoinst";
our $perldir="$basedir/$perlurl";
our $resultdir="$basedir/$prj/testresults";
our $scheduledir="$basedir/$prj/schedule.d";
our $loguploaddir="$basedir/$prj/logupload";
our $hostname=$ENV{'SERVER_NAME'};
our $app_title = 'openQA test instance';
our $app_subtitle = 'openSUSE automated testing';

our $dbfile = "$basedir/$prj/db/db.sqlite";

our @runner = <$basedir/$prj/pool/[0-9]>;
push(@runner, "$basedir/$prj/pool/manual");

our $res_css = {
	'na' => 'not-autochecked',
	'unk' => 'unknown',
	'ok' => 'ok',
	'fail' => 'fail'
};

our $res_display = {
	'na' => 'n/a',
	'unk' => 'unknown',
	'ok' => 'OK',
	'fail' => 'FAIL'
};



sub test_result($) {
	my $testname = shift;
	my $testresdir = testresultdir($testname);
	local $/;
	open(JF, "<", "$testresdir/results.json") || return;
	return unless fcntl(JF, F_SETLKW, pack('ssqql', F_RDLCK, 0, 0, 0, $$));
	my $result_hash;
	eval {
		$result_hash = decode_json(<JF>);
	}; warn "failed to parse $testresdir/results.json: $@" if $@;
	close(JF);
	return $result_hash;
}

sub test_result_hash($) {
	# produce old simple key-val hash of all results
	my $result_hash = shift;
	my $result_simple_hash = {};
	my $module;
	for $module (@{$result_hash->{'testmodules'}}) {
		$result_simple_hash->{$module->{'name'}} = $module->{'result'};
	}
	for $module ("standstill", "overall") {
		if(defined $result_hash->{$module}) {
			$result_simple_hash->{$module} = $result_hash->{$module};
		}
	}
	return $result_simple_hash;
}

sub test_result_stats($) {
	my $result_hash = shift;
	my $result_stat = {'ok' => 0, 'fail' => 0, 'unk' => 0, 'na' => 0};
	my $result_simple_hash = test_result_hash($result_hash);
	for my $module (keys %{$result_simple_hash}) {
		$result_stat->{$result_simple_hash->{$module}}++;
	}
	return $result_stat;
}

sub test_result_module($$) {
	# get a certain testmodule subtree
	my $modules_array = shift;
	my $query_module = shift;
	for my $module (@{$modules_array}) {
		if($module->{'name'} eq $query_module) {
			return $module;
		}
	}
}

sub parse_log($) {
	my($fn)=@_;
	open(my $fd, "<", $fn) || return;
	seek($fd, -4095, 2);
	my $logdata;
	read($fd,$logdata,100000);
	close($fd);

	# assume first log line is splashscreen:
	return () unless $logdata=~s/.*====\n//s;
	my @lines=map {[split(": ")]} split("\n",$logdata);
	return @lines;
}

sub parse_log_to_stats($) {
	my($lines)=@_;
	my %stats;
	foreach my $entry (@$lines) {
		my $result=$entry->[1];
		$result=~s/\s.*//;
		$stats{$result}++;
	}
	return \%stats;
}

sub parse_log_to_hash($) {
	my($lines)=@_;
	my %results=();
	foreach my $entry (@$lines) {
		$results{$entry->[0]}=$entry->[1];
	}
	return \%results;
}


sub _regexp_parts
{
    my $distri = '(openSUSE|SLES)';
    my $version = '(\d+.\d|\d+-SP\d|Factory)';
    my $flavor = '(Addon-(?:Lang|NonOss)|(?:Promo-)?DVD(?:-BiArch|-OpenSourcePress)?|NET|(?:GNOME|KDE)-Live|Rescue-CD|MINI-ISO|staging_[^-]+)';
    my $arch = '(i[356]86(?:-x86_64)?|x86_64|i586-x86_64|ia64|ppc64|s390x)';
    my $build = '(Build(?:\d+))';

    return ($distri, $version, $flavor, $arch, $build);
}

sub parse_testname($)
{
    my $name = shift;
    my ($distri, $version, $flavor, $arch, $build) = _regexp_parts;

    my @parts = $name =~ /^$distri(?:-$version)?-$flavor-$arch(?:-$build)?-(.+)$/i;

    return undef unless @parts;

    my %params;
    @params{qw(distri version flavor arch build extrainfo)} = @parts;

    if (wantarray()) {
	return %params;
    }
    else {
	return \%params;
    }
}

sub parse_iso($) {
    my $iso = shift;

    my ($distri, $version, $flavor, $arch, $build) = _regexp_parts;

    my @parts = $iso =~ /^$distri(?:-$version)?-$flavor(?:-$build)?-$arch.*\.iso$/i;

    my $order = 1;
    if (!$parts[3] ) {
	@parts = $iso =~ /^$distri(?:-$version)?-$flavor-$arch(?:-$build)?.*\.iso$/i;
	$order = 2;
    }

#    foreach (@parts) {
#	print STDERR "{$_}\n";
#    }
#
    if( @parts ) {
        my %params;
	if ($order == 1) {
	    @params{qw(distri version flavor build arch)} = @parts;
	} else {
	    @params{qw(distri version flavor arch build)} = @parts;
	}
        $params{version} ||= 'Factory';
        
        if (wantarray()) {
            return %params;
        }
        else {
            return \%params;
        }
    }
    else {
        return undef;
    }
}

# find the full pathname to a given testrun-logfile and test name
# FIXME: what a crap
sub log_to_scriptpath($$)
{ my($fn,$testname)=@_;
	open(my $fd, "<", $fn) or return undef;
	while(my $line=<$fd>) {
		next unless $line=~m/^(?:scheduling|\|\|\| starting|starting) $testname (\S*)/;
		return $1;
	}
	return undef;
}

sub running_log($) {
	my $name = shift;
	my $dest = readlink("$basedir/$prj/testresults/$name");
	return '' unless $dest;
	return dirname(dirname($dest)).'/';
}

sub back_log($) {
	my ($name) = @_;
	my $backlogdir = "*";
	my @backlogs = <$basedir/$prj/backlog/$backlogdir/name>;
	foreach my $filepath (@backlogs) {
		my $path = $filepath;
		$path=~s/\/name$//;
		open(my $fd, $filepath) || next ;
		my $rnam = <$fd>;
		chomp($rnam);
		close($fd);
		if ($name eq $rnam) {
			return $path."/";
		}
	}
	return "";
}

sub running_state($) {
	my ($name) = @_;
	my $dir = running_log($name);
	my $pid = file_content("$dir/os-autoinst.pid");
	chomp($pid);
	my $state = file_content("/proc/$pid/status") || "";
	$state=~m/^State:\s+(\w)\s/m;
	$state = $1;
	return ($state eq "T")?0:1;
}

sub get_running_modinfo($) {
	my $results = shift;
	return {} unless $results;
	my $currentstep = $results->{'running'}||'';
	my $modlist = [];
	my $donecount = 0;
	my $count = @{$results->{'testmodules'}};
	my $modstate = 'done';
	my $category;
	for my $module (@{$results->{'testmodules'}}) {
		my $name = $module->{'name'};
		my $result = $module->{'result'};
		if (!$category || $category ne $module->{'category'}) {
			$category = $module->{'category'};
			push(@$modlist, {'category' => $category, 'modules' => []});
		}
		if ($name eq $currentstep) {
			$modstate = 'current';
		} elsif ($modstate eq 'current') {
			$modstate = 'todo';
		} elsif ($modstate eq 'done') {
			$donecount++;
		}
		my $moditem = {'name' => $name, 'state' => $modstate, 'result' => $result};
		push(@{$modlist->[scalar(@$modlist)-1]->{'modules'}}, $moditem);
	}
	return {'modlist' => $modlist, 'modcount' => $count, 'moddone' => $donecount, 'running' => $results->{'running'}};
}


# get testname by name or path
sub path_to_testname($) {
	my $fn=shift;
	$fn=~s%\.autoinst\.txt$%%;
	$fn=~s%\.ogv$%%;
	$fn=~s%.*/%%;
	return $fn;
}

sub testresultdir($) {
	my $fn=shift;
	$fn=~s%\.autoinst\.txt$%%;
	$fn=~s%\.ogv$%%;
	"$basedir/$prj/testresults/$fn";
}

sub split_filename($) { my($fn)=@_;
	my $origfn=$fn;
	$fn=~s%\.autoinst\.txt$%%; # strip suffix
	$fn=~s%\.ogv$%%; # strip suffix
	$fn=~s%.*/%%; # strip path

	# since we want to split at "-", this should not appear within fields
	$fn=~s/(openSUSE)-(1\d\.\d|Factory)/$1_$2/; # since 2013-02-05 isos have the distri version included in the name
	$fn=~s/Promo-DVD/DVD_Promo/;
	$fn=~s/DVD-Biarch-i586-x86_64/DVD_Biarch-i586+x86_64/;
	$fn=~s/-Live/_Live/; # belongs to KDE/GNOME, so protect from split
	$fn=~s/-CD-/_CD-/; # for Rescue-CD
	$fn=~s/(SLE.)-(\d+)-(SP|G)/$1_$2_$3/;
	my @a=split("-",$fn);
	$a[3]=~s/Build//;
	$a[4]||=""; # extrainfo is optional
	return (@a);
}

sub test_resultfile_list($) {
	# get a list of existing resultfiles
	my $testname = shift;
	my $testresdir = testresultdir($testname);
	my @filelist = qw(results.json backend.json serial0.txt autoinst-log.txt);
	my @filelist_existing;
	for my $f (@filelist) {
		if(-e "$testresdir/$f") {
			push(@filelist_existing, $f);
		}
	}
	return @filelist_existing;
}

sub test_uploadlog_list($) {
	# get a list of uploaded logs
	my $testname = shift;
	my $testresdir = testresultdir($testname);
	my @filelist;
	for my $f (<$testresdir/ulogs/*>) {
	       $f=~s#.*/##;
	       push(@filelist, $f);
	}
	return @filelist;
}

sub resultname_to_log($)
{ testresultdir($_[0])."/autoinst-log.txt";
}
sub resultname_to_url($)
{ "http://$hostname/results/$_[0]"; 
}

sub is_authorized_rw()
{
	my $ip=$ENV{REMOTE_ADDR};
	my $mapatterns=$ENV{OPENQA_MATCHED_PATTERNS};
	my $allowedips=$ENV{OPENQA_ALLOWED_HOSTS};

	# compare to the pattern
	my @mapattern=split(' ',$mapatterns);
	foreach my $val (@mapattern) {
		return 1 if($ip =~ m/$val/);
	}

	# compare to the ip
	my @allowedip=split(' ',$allowedips);
	foreach my $val (@allowedip) {
		return 1 if($ip eq $val);
	}

	return 0;
}

sub is_scheduled($)
{
	my $testname=shift;
	return -e "$scheduledir/$testname";
}

sub get_testimgs($)
{ my $name=shift;
	my @a=<$perldir/testimgs/$name-*>; # needs to be in list context
	return @a;
}

sub get_waitimgs($)
{ my $name=shift;
	my @a=<$perldir/waitimgs/$name-*>; # needs to be in list context
	return @a;
}

sub get_clickimgs($)
{ my $name=shift;
	my @a=<$perldir/waitimgs/click/$name-*>; # needs to be in list context
	return @a;
}

sub get_testwavs($)
{ my $name=shift;
	my @a=<$perldir/audio/$name-*>; # needs to be in list context
	return @a;
}

sub testimg($)
{ my $name=shift;
	return "$perldir/testimgs/$name";
}

sub clickimg($)
{ my $name=shift;
	return "$perldir/waitimgs/click/$name";
}


our $table_row_style = 0;
sub cycle(;$) {
	my $cset = shift||0;
	if($cset == 1) {
		$table_row_style = 0;
		return;
	}
	if($cset != 2) { # 2 means read without toggle
		$table_row_style^=1; # toggle state
	}
	return $table_row_style?'odd':'even';
}

our $loop_first_run = 1;
sub first_run(;$) {
	if(shift) {
		$loop_first_run = 1;
		return;
	}
	if($loop_first_run) {
		$loop_first_run = 0;
		return 1;
	}
	else {
		return 0;
	}
}

sub sortkeys($$) {
	my $options = shift;
	my $sortname = shift;
	my $suffix = "";
	$suffix .= ".".$options->{'sort'}.(defined($options->{'hours'})?"&amp;hours=".$options->{'hours'}:"");
	$suffix .= (defined $options->{'match'})?"&amp;match=".$options->{'match'}:"";
	$suffix .= ($options->{'ib'})?"&amp;ib=on":"";
	my $dn_url = "?sort=-".$sortname.$suffix;
	my $up_url = "?sort=".$sortname.$suffix;
	return '<a rel="nofollow" href="'.$dn_url.'"><img src="/images/ico_arrow_dn.gif" style="border:0" alt="sort dn" /></a><a rel="nofollow" href="'.$up_url.'"><img src="/images/ico_arrow_up.gif" style="border:0" alt="sort up" /></a>';
}

sub syntax_highlight($)
{
	my $script=shift;
	$script=~s{^sub is_applicable}{# this function decides if the test shall run\n$&}m;
	$script=~s{^sub run}{# this part contains the steps to run this test\n$&}m;
	$script=~s{^sub checklist}{# this part contains known hash values of good or bad results\n$&}m;
	eval "require Perl::Tidy;" or return "<pre>$script</pre>";
	push(@ARGV,"-html", "-css=/dev/null");
	my @out;
	Perl::Tidy::perltidy(
		source => \$script,
		destination => \@out,
	);
	my $out=join("",@out);
	#$out=~s/.*<body>//s;
	$out=~s/.*<!-- contents of filename: perltidy -->//s;
	$out=~s{</body>.*}{}s;
	return $out;
}

sub data_name($) {
	$_[0]=~m/^.*\/(.*)\.\w\w\w(?:\.gz)?$/;
	return $1;
}

sub parse_refimg_path($) {
	$_[0]=~m/.*\/(\w+)-(\d+)-(\d+)-(\w+)-(\w+)\.png/;
	return ($1,$2,$3,$4,$5);
}
sub parse_refimg_name($) {
	my($testmodule,$screenshot,$n,$result,$match)=parse_refimg_path($_[0]);
	return {name => "$testmodule-$screenshot-$n-$result-$match", result => $result, match => $match, id => $n};
}

sub match_title($) {
	my $match = shift;
	my %titles = (
		'strict' => 'The refimg has to match exactly',
		'diff' => 'Each byte of the refimg may have an offset',
		'hwfuzzy' => 'Fuzzy matching on hardware-tests, otherwise diff matching',
		'fuzzy' => 'Vector based fuzzy matching using openCV'
	);
	return $titles{$match};
}

sub needle_info($$) {
	my $name = shift;
	my $distri = shift;
	local $/;

	my $needledir = "distri/$distri/needles";

	my $fn = "$perldir/$needledir/$name.json";
	unless (open(JF, '<', $fn )) {
		warn "$fn: $!";
		return undef;
	}
	my $needle = decode_json(<JF>) || return undef ;
	close(JF);

	$needle->{'image'} = "$perldir/$needledir/$name.png";
	$needle->{'json'} = "$perldir/$needledir/$name.json";
	$needle->{'imageurl'} = "/$perlurl/$needledir/$name.png";
	$needle->{'jsonurl'} = "/$perlurl/$needledir/$name.json";
	return $needle;
}

sub get_failed_needles(@)
{
	my %args = @_;
	my $how = $args{'ordering'}||'byname';
	my $pattern = $args{'pattern'}||'*';
	my $glob = "$resultdir/$pattern/results.json";
	my $failures = {};
	for my $fn (glob $glob) {
		local $/; # enable localized slurp mode
		next unless -e $fn;
		open (my $fd, '<', $fn);
		next unless $fd;
		my $results = decode_json(<$fd>);
		close $fn;
		my $name = $fn;
		$name =~ s,.*/([^/]+)/results.json$,$1,;
		for my $module (@{$results->{testmodules}}) {
			next unless $module->{result} eq 'fail';
			next if ($args{fatal} && ! $module->{flags}->{fatal});
			for my $detail (@{$module->{details}}) {
				next unless $detail->{result} eq 'fail';
				next unless $detail->{needles};
				for my $needle (@{$detail->{needles}}) {
					if ($how eq 'byname') {
						push @{$failures->{$name}->{$module->{name}}}, {
							needle=> $needle->{name},
							error => $needle->{error}||undef
						};
					} elsif ($how eq 'byneedle') {
						push @{$failures->{$needle->{name}}}, $name;
					}
				}
			}
		}
	}
	return $failures;
}

sub sanitize_testname($)
{
	my $name = shift;
	$name =~ s/[^a-zA-Z0-9._+-]//g;
	return undef unless $name =~ /^[a-zA-Z]/;
	return $name;
}

1;

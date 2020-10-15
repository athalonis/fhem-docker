# $Id: 98_KMS.pm 2016 stefanbaer $

##############################################################################
#
#     98_KMS.pm
#     Copyright 2016 Stefan Baer
#
#     Dank an Rudolf König - Idee und Grundaufbau aus dem 00_KM271.pm Modul
#     Dank an Dr. Boris Neubert - Grundlage des KMS Moduls ist 66_ECMD.pm
#     Dank an narsskrarc - Polling habe ich mir aus dem 34_NUT.pm abgeschaut
#
##############################################################################

package main;
use strict;
use warnings;
use Time::HiRes qw(gettimeofday);
use DevIo;
#use Data::Dump qw(dump);

sub KMS_Initialize($);		#Initialisierung
sub KMS_Define($$);			#Define
sub KMS_Undef($$);			#Undefine
sub KMS_Ready($);			#ReadyStatus
sub KMS_DoInit($);			#DoInit
sub KMS_DebugComment($);	#Auskommentierung von Logeinträgen
sub KMS_SimpleRead($);		#DevIO SimpleRead Funktion
sub KMS_SimpleWrite($$);	#DevIO SimpleWrite Funktion
sub KMS_SimpleExpect($$$);	#DevIO SimpleExpect (Schreibe und lies dann bis Zeilenende) wird von pollStatus und Get aufgerufen
sub KMS_Get($@);			#Get Funktion
sub KMS_pollStatus($);		#fragt alle Werte zyklisch nach pollTimer ab und ruft dann WriteKmsArray auf (schreibt auch die Readings)
sub KMS_pollTimer($);		#pollTimer Zyklus wird durch das attr pollTime in sekunden festgelegt
sub KMS_WriteKmsArray($$);	#bearbeitet das @kms_array und fügt die aktullen werte hinzu oder ändert diese
sub KMS_Reopen($);			#öffnet die Verbindung erneut, wird durch SET reopen aufgerufen
sub KMS_Set($@);			#Set Funktion
sub KMS_Read($);			#Read funktion wird von der globalen Schleife aufgerufen (nicht benötigt)


use vars qw {%attr %defs};


#KMS_Get Funktionen
my %kms_gets = (
  "RAW"           			=> "",
  "Zeitplan_HK1_1"			=> ":Timespan,Bitstring",
  "Zeitplan_HK1_2"			=> ":Timespan,Bitstring",
  "Zeitplan_HK2_1"			=> ":Timespan,Bitstring",
  "Zeitplan_HK2_2"			=> ":Timespan,Bitstring",
  "Zeitplan_WW_1"			=> ":Timespan,Bitstring",
  "Zeitplan_WW_2"			=> ":Timespan,Bitstring",
  "Status"               	=> ":noArg"
);

#KMS_Set Funktionen
my %kms_sets = (
  "HK1_Nacht_Soll"			=> {SET => "80100008000102_VALUE_LRC",
								OPT => ":slider,10,0.5,30,1"},
  "HK1_Tag_Soll"			=> {SET => "80100007000102_VALUE_LRC",
								OPT => ":slider,10,0.5,30,1"},
  "HK1_Betriebsart"			=> {SET => "80100006000102_VALUE_LRC",
								OPT => ":Automatik,Tag,Nacht,Aus"},
  "HK1_Zeitprogramm"		=> {SET => "80100006000102_VALUE_LRC",
								OPT => ":1,2"},
  "HK1_Sondermodus"			=> {SET => "80100009000306_VALUE_LRC",
								OPT => ":textField"},				# Party|Eco 19:15 23.5 , Urlaub 19.07. 18.0 , 0 = löschen
  "HK2_Nacht_Soll"			=> {SET => "8010000E000102_VALUE_LRC",
								OPT => ":slider,10,0.5,30,1"},
  "HK2_Tag_Soll"			=> {SET => "8010000D000102_VALUE_LRC",
								OPT => ":slider,10,0.5,30,1"},
  "HK2_Betriebsart"			=> {SET => "8010000C000102_VALUE_LRC",
								OPT => ":Automatik,Tag,Nacht,Aus"},
  "HK2_Zeitprogramm"		=> {SET => "8010000C000102_VALUE_LRC",
								OPT => ":1,2"},
  "HK2_Sondermodus"			=> {SET => "8010000F000306_VALUE_LRC",
								OPT => ":textField"},				# Party|Eco 19:15 23.5 , Urlaub 19.07. 18.0 , 0 = löschen
  "WW_Soll"					=> {SET => "80100013000102_VALUE_LRC",
								OPT => ":slider,30,1,70"},
  "WW_Betriebsart"			=> {SET => "80100012000102_VALUE_LRC",
								OPT => ":Automatik,Tag,Aus"},
  "WW_Zeitprogramm"			=> {SET => "80100012000102_VALUE_LRC",
								OPT => ":1,2"},
  "WW_Sondermodus"			=> {SET => "80100015000306_VALUE_LRC",
								OPT => ":textField"},				# 1 = 1x Warm Machen, 0 = Löschen
  "ZH_USB_Device_Reopen"	=> {SET => "reopen",
								OPT => ":noArg"}
);

# startIndex, länge, hexwert, zieldatentyp (f=float, d=decimal, b=binär, z=datetime), 
# operation (a=addiere,s=subtrahiere,m=multipliziere,d=dividiere,l=minimalestringlänge,p=bitposition,n=nichts,b=byte,sm=sondermodus,zw=Zählwert),
# operationswert, realwert, einheit, readingname
my @kms_array = (
	[  7,12, "","z","n",   0,  "",  "","Datum_Zeit"],
	[ 31, 4, "","s","b",   1,  "",  "","HK1_Zeitprogramm"],
	[ 31, 4, "","s","b",   0,  "",  "","HK1_Betriebsart"],
	[ 35, 4, "","f","d",  10,  "","°C","HK1_Tag_Soll"],
	[ 39, 4, "","f","d",  10,  "","°C","HK1_Nacht_Soll"],
	[ 43,12, "","s","sm",  0,  "",  "","HK1_Sondermodus"],
	[ 55, 4, "","s","b",   1,  "",  "","HK2_Zeitprogramm"],
	[ 55, 4, "","s","b",   0,  "",  "","HK2_Betriebsart"],
	[ 59, 4, "","f","d",  10,  "","°C","HK2_Tag_Soll"],
	[ 63, 4, "","f","d",  10,  "","°C","HK2_Nacht_Soll"],
	[ 67,12, "","s","sm",  0,  "",  "","HK2_Sondermodus"],
	[ 79, 4, "","s","b",   1,  "",  "","WW_Zeitprogramm"],
	[ 79, 4, "","s","b",   0,  "",  "","WW_Betriebsart"],
	[ 83, 4, "","f","d",  10,  "","°C","WW_Soll"],
	[ 87,12, "","s","sm",  0,  "",  "","WW_Sondermodus"],
	[159, 4, "","f","d",  10,  "","°C","ZT_T1_Ist"],
	[163, 4, "","f","d",  10,  "","°C","ZT_T2_Ist"],
	[167, 4, "","f","d",  10,  "","°C","ZT_T3_Ist"],
	[171, 4, "","f","d",  10,  "","°C","ZT_T4_Ist"],
	[175, 4, "","f","d",  10,  "","°C","ZT_T5_Ist"],
	[179, 4, "","f","d",  10,  "","°C","ZT_T6_Ist"],
	[183, 4, "","f","d",  10,  "","°C","ZT_T7_Ist"],
	[187, 4, "","f","d",  10,  "","°C","ZT_T8_Ist"],
	[191, 4, "","f","d",  10,  "","°C","ZT_TR1_Ist"],
	[195, 4, "","f","d",  10,  "","°C","ZT_TR2_Ist"],
	[203, 4, "","f","d",  10,  "","°C","ZT_T1_Soll"],
	[207, 4, "","f","d",  10,  "","°C","ZT_T2_Soll"],
	[211, 4, "","f","d",  10,  "","°C","ZT_T3_Soll"],
	[215, 4, "","f","d",  10,  "","°C","ZT_T4_Soll"],
	[219, 4, "","f","d",  10,  "","°C","ZT_T5_Soll"],
	[223, 4, "","f","d",  10,  "","°C","ZT_T6_Soll"],
	[227, 4, "","f","d",  10,  "","°C","ZT_T7_Soll"],
	[231, 4, "","f","d",  10,  "","°C","ZT_T8_Soll"],
	[235, 4, "","f","d",  10,  "","°C","ZT_TR1_Soll"],
	[239, 4, "","f","d",  10,  "","°C","ZT_TR2_Soll"],
	[149, 2, "","b","l",   8,  "",  "",".ZR_RX"],
	[149, 2, "","b","p",   7,  "",  "","ZR_R1"],
	[149, 2, "","b","p",   6,  "",  "","ZR_R2"],
	[149, 2, "","b","p",   5,  "",  "","ZR_R3"],
	[149, 2, "","b","p",   4,  "",  "","ZR_R4"],
	[149, 2, "","b","p",   3,  "",  "","ZR_R5"],
	[149, 2, "","b","p",   2,  "",  "","ZR_R6"],
	[149, 2, "","b","p",   1,  "",  "","ZR_R7"],			#Index 42
	[149, 2, "","b","p",   0,  "",  "","ZR_R8"],
	[  1, 2, "","n", "",   0,  "",  "",".Placeholder"],	
	[  1, 2, "","n", "",   0,  "",  "",".Placeholder"],	
	[  1, 2, "","n", "",   0,  "",  "",".Placeholder"],	
	[  1, 2, "","n", "",   0,  "",  "",".Placeholder"],	
	[  1, 2, "","n", "",   0,  "",  "",".Placeholder"],	
	[  1, 2, "","n", "",   0,  "",  "",".Placeholder"],	
	[  1, 2, "","n", "",   0,  "",  "",".Placeholder"],	#index 50
	[  1, 2, "","n", "",   0,  "",  "",".Placeholder"],	
	[  1, 2, "","n", "",   0,  "",  "",".Placeholder"],	
	[  1, 2, "","n", "",   0,  "",  "",".Placeholder"],	
	[  1, 2, "","n", "",   0,  "",  "",".Placeholder"],	
	[  1, 2, "","n", "",   0,  "",  "",".Placeholder"],	
	[  1, 2, "","n", "",   0,  "",  "",".Placeholder"],	
	[  1, 2, "","n", "",   0,  "",  "",".Placeholder"],	
	[  1, 2, "","n", "",   0,  "",  "",".Placeholder"],	
	[  1, 2, "","n", "",   0,  "",  "",".Placeholder"],	
	[  7, 4, "","zw", "",   0,  "",  "","ZW_R1"],       #index 60
	[ 11, 4, "","zw", "",   1,  "",  "","ZW_R2"],
	[ 15, 4, "","zw", "",   2,  "",  "","ZW_R3"],
	[ 19, 4, "","zw", "",   3,  "",  "","ZW_R4"],
	[ 23, 4, "","zw", "",   4,  "",  "","ZW_R5"],
	[ 27, 4, "","zw", "",   0,  "",  "","ZW_R6"],
	[ 31, 4, "","zw", "",   0,  "",  "","ZW_R7"],
	[ 35, 4, "","zw", "",   0,  "",  "","ZW_R8"],
	[ 39, 4, "","zw", "",   0,  "",  "","ZW_R9"],
	[ 43, 4, "","zw", "",   0,  "",  "","ZW_R0"],
	[ 47, 4, "","zw", "",   0,  "",  "","ZW_R1_Starts_Gesamt"],
	[ 51, 4, "","zw", "",   0,  "",  "","ZW_R1_Starts_Heute"],
	[ 55, 4, "","zw", "",   0,  "",  "","ZW_R1_Betriebsstunden_Gesamt"],
	[ 59, 4, "","zw", "",   0,  "",  "","ZW_R0_Starts_Gesamt"],
	[ 63, 4, "","zw", "",   0,  "",  "","ZW_R0_Starts_Heute"],
	[ 67, 4, "","zw", "",   0,  "",  "","ZW_R0_Betriebsstunden_Gesamt"],
);

my @kms_hk_betriebsarten = ("Automatik","Tag","Nacht","Aus");
my @kms_hk_sondermodus   = ("Aus","Party","Eco","Urlaub");
my @kms_ww_betriebsarten = ("Automatik","Tag","Aus");
my @kms_ww_sondermodus   = ("Aus","Warmmachen");
my @kms_zeitprogramm     = ("1","2");

my @kms_schaltarray  = ("00","15","30","45");

#####################################
sub KMS_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}   = "KMS_Define";
  $hash->{UndefFn} = "KMS_Undef";
  $hash->{ReadFn}  = "KMS_Read";
  $hash->{ReadyFn} = "KMS_Ready";
  $hash->{GetFn}   = "KMS_Get";
  $hash->{SetFn}   = "KMS_Set";
  $hash->{AttrList}= "debugModus:0,1 updateTime:0,1 pollTime:1,2,3,4,5,6,7,8,9,10 useHK2:0,1 disable:0,1 timeout:1,2,3,4,5,6,7,8,9,10 partial:0,1,2,3,4,5,6,7,8,9,10 pollRunTime ".
					 #"hk1_Party_Temp:18.0,18.5,19.0,19.5,20.0,20.5,21.0,21.5,22.0,22.5,23.0,23.5,24.0,24.5,25.0 ".
					 #"hk1_Eco_Temp:10.0,10.5,11.0,11.5,12.0,12.5,13.0,13.5,14.0,14.5,15.0,15.5,16.0,16.5,17.0,17.5,18.0,18.5,19.0,19.5,20.0 ".
					 #"hk1_Urlaub_Temp:10.0,10.5,11.0,11.5,12.0,12.5,13.0,13.5,14.0,14.5,15.0,15.5,16.0,16.5,17.0,17.5,18.0,18.5,19.0,19.5,20.0 ".
					 #"hk2_Party_Temp:18.0,18.5,19.0,19.5,20.0,20.5,21.0,21.5,22.0,22.5,23.0,23.5,24.0,24.5,25.0 ".
					 #"hk2_Eco_Temp:10.0,10.5,11.0,11.5,12.0,12.5,13.0,13.5,14.0,14.5,15.0,15.5,16.0,16.5,17.0,17.5,18.0,18.5,19.0,19.5,20.0 ".
					 #"hk2_Urlaub_Temp:10.0,10.5,11.0,11.5,12.0,12.5,13.0,13.5,14.0,14.5,15.0,15.5,16.0,16.5,17.0,17.5,18.0,18.5,19.0,19.5,20.0 ".
					 #"hk1_Party_Time:1h,2h,3h,4h,5h,6h,7h,8h,9h,10h,11h,12h,13h,14h,15h,16h,17h,18h,19h,20h,21h,22h,23h ".
					 #"hk1_Eco_Time:1h,2h,3h,4h,5h,6h,7h,8h,9h,10h,11h,12h,13h,14h,15h,16h,17h,18h,19h,20h,21h,22h,23h ".
					 #"hk1_Urlaub_Days:1d,2d,3d,4d,4d,6d,7d,8d,9d,10d,11d,12d,13d,14d,15d,16d,17d,18d,19d,20d,21d,22d,23d,24d,25d,26d,27d,28d ".
					 #"hk2_Party_Time:1h,2h,3h,4h,5h,6h,7h,8h,9h,10h,11h,12h,13h,14h,15h,16h,17h,18h,19h,20h,21h,22h,23h ".
					 #"hk2_Eco_Time:1h,2h,3h,4h,5h,6h,7h,8h,9h,10h,11h,12h,13h,14h,15h,16h,17h,18h,19h,20h,21h,22h,23h ".
					 #"hk2_Urlaub_Days:1d,2d,3d,4d,4d,6d,7d,8d,9d,10d,11d,12d,13d,14d,15d,16d,17d,18d,19d,20d,21d,22d,23d,24d,25d,26d,27d,28d ".
					 $readingFnAttributes;
	#$hash->{parseParams} = 1;
}

#####################################
sub KMS_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t]+", $def);

  my $name = $a[0];

  if(@a < 3 || @a > 3) {
    my $msg = "wrong syntax: define <name> KMS <devicename[\@baudrate]>";
    return $msg;
  }
  
  $attr{$name}{disable} = 0;
  $attr{$name}{updateTime} = 0;
  $attr{$name}{debugModus} = 0;
  $attr{$name}{pollTime} = 1;
  $attr{$name}{partial} = 1;
  $attr{$name}{timeout} = 1;
  $attr{$name}{pollRunTime} = 30;
  $attr{$name}{useHK2} = 0;
  
  DevIo_CloseDev($hash);

  $hash->{DeviceName} = $a[2];
  $hash->{pollTimeState} = 0; # in seconds
  $hash->{pollGetState} = 0; # 0 Polling Normal, 1 Get State

  return DevIo_OpenDev($hash, 0, "KMS_DoInit");
}


#####################################
sub KMS_Undef($$)
{
  my ($hash, $arg) = @_;
  my $name = $hash->{NAME};

  RemoveInternalTimer("pollTimer:".$name);
  DevIo_CloseDev($hash);
  return undef;
}

#####################################
sub KMS_Ready($) 
{
  my ($hash) = @_;
  return DevIo_OpenDev($hash, 1, "KMS_DoInit");
}

#####################################
sub KMS_DoInit($)
{
  my ($hash) = @_;
  $hash->{pollTimeState} = 0; # in seconds
  $hash->{pollGetState} = 0; # 0 Polling Normal, 1 Get State
  
  KMS_pollStatus($hash);

  return undef;
}

#####################################
sub KMS_DebugComment($) 
{
  my ($s)= @_;
  $s= "<nothing>" unless(defined($s));
  return "\"" . escapeLogLine($s) . "\"";
}

#####################################
sub KMS_SimpleRead($) 
{
  my $hash = shift;
  my $name= $hash->{NAME};
  my $answer= DevIo_SimpleRead($hash);
  Log3 $name, 4, "$name: read " . KMS_DebugComment($answer);
  return $answer;
}

sub KMS_SimpleWrite($$) 
{
  my ($hash, $msg) = @_;
  my $name= $hash->{NAME};
  Log3 $name, 4, "$name: write " . KMS_DebugComment($msg);
  DevIo_SimpleWrite($hash, $msg, 0);
}

sub KMS_SimpleExpect($$$)
{
  my ($hash, $msg, $expect) = @_;
  
  my $name= $hash->{NAME};
  my $timeout= AttrVal($name, "timeout", 3.0);
  my $partialTimeout= AttrVal($name, "partial", 0.0);
 
  Log3 $name, 4, "$name: schreibe mit SimpleExpect" . KMS_DebugComment($msg) . ", expect $expect";
  
  my $answer= DevIo_Expect($hash, $msg, $timeout );
  
  # complete partial answers
  if($partialTimeout> 0) {
    my $t0= gettimeofday();
    while(!defined($answer) || ($answer !~ /^$expect$/)) {
      my $a= DevIo_SimpleReadWithTimeout($hash, $partialTimeout);
      if(defined($a)) {
			$answer= ( defined($answer) ? $answer . $a : $a );
      }
      last if(gettimeofday()-$t0> $partialTimeout);
    }
  }
  
  if(defined($answer)) {
    if($answer !~ m/^$expect$/) {
		Log3 $name, 4, "$name: unvollständige Antwort mit SimpleExpect empfangen: " . KMS_DebugComment($answer);
    }else{
		Log3 $name, 4, "$name: gelesen mit SimpleExpect: " . KMS_DebugComment($answer);
	}
  } else {
    Log3 $name, 4, "$name: Keine Antwort mit SimpleExpect empfangen";
  }
  
  return $answer;
}

#####################################
sub KMS_Get($@)
{
	my ($hash, @a) = @_;
  
	return "KMS get needs at least an argument" if(@a < 2);
 
	my $name = $a[0];
	my $cmd= $a[1];
	my $arg = ($a[2] ? $a[2] : "");
	my @args= @a; shift @args; shift @args;
	my ($answer, $err, $msg);
  
	my $head = ":";
	my $foot = "\r\n";
	my $expect = ".*\\r\\n";		
	
	
	if(!defined($kms_gets{$cmd})) {
		my $msg = "";
		foreach my $para (sort keys %kms_gets) {
			if ($attr{$name}{useHK2} == 0 && $para=~/^Zeitplan_HK2/){
				$msg .= '';
			}else{
				$msg .= " $para" . $kms_gets{$para};
			}
		}
		return "$name Unknown argument $cmd, choose one of" . $msg;
	}

	return "$name No get $cmd for dummies" if(IsDummy($name));
	
	my $ret = '';
	
	if($cmd eq "RAW") {
  
		return "$name get raw needs two arguments. offset (int) and length (int)" if(@a < 4);
		return "$name get raw needs two arguments. offset (int) and length (int)*4" if($a[2]%1 != 0 || $a[3]%1 != 0);
		RemoveInternalTimer("pollTimer:".$name);
		
		$msg = $head.KMS_LRC("8003".sprintf("%04X",$a[2]).sprintf("%04X",$a[3])).$foot;
		
		#$msg = $head.join(" ",@args).$foot;
		
		$answer = "";
        $answer = KMS_SimpleExpect($hash, $msg, $expect);
		
		my $offset = $a[2]+0;
		my $length = $a[3]+0;
		my $register = 40001+$offset;
		my $substr = "";
		
		if(@a<5){
		
			$ret = "reg\thex\tdecimal\n";
			for(my $i=0;$i<$length;$i++){
				$substr = substr($answer,($i*4)+7,4);
				$ret.=($register+$i)."\t".$substr."\t".hex($substr)."\t\n";
			}
			
		}else{
			if($a[4] eq "bit"){
			
				for(my $i=0;$i<$length*2;$i++){
					$substr = substr($answer,($i*2)+7,2);
					$ret.=reverse(sprintf("%08d",sprintf("%b",hex($substr))));
				}
				
			}else{
				$ret = $answer;
			}
		}
		
	}elsif($cmd =~ /^Zeitplan/){
		return "$name get Heizplan needs one more argument." if(@a<2);
		RemoveInternalTimer("pollTimer:".$name);
		
		my $plan = 0;
		
		if($a[1] eq "Zeitplan_HK1_1"){
			$plan = 0;
		}elsif($a[1] eq "Zeitplan_HK1_2"){
			$plan = 42;
		}elsif($a[1] eq "Zeitplan_HK2_1"){
			$plan = 84;
		}elsif($a[1] eq "Zeitplan_HK2_2"){
			$plan = 126;
		}elsif($a[1] eq "Zeitplan_WW_1"){
			$plan = 168;
		}elsif($a[1] eq "Zeitplan_WW_2"){
			$plan = 210;
		}
		
		my $offset = 700+$plan;
		my $length = 42;
		my $substr = "";
		my @days = ("Montag","Dienstag","Mittwoch","Donnerstag","Freitag","Samstag","Sonntag");		
		$msg = $head.KMS_LRC("8003".sprintf("%04X",$offset).sprintf("%04X",$length)).$foot;
		
		$answer = "";
        $answer = KMS_SimpleExpect($hash, $msg, $expect);
		
		
		if($a[2] eq "Timespan"){
			for(my $i=0;$i<$length*2;$i++){
				$substr = substr($answer,($i*2)+7,2);
				$ret.= reverse(sprintf("%08d",sprintf("%b",hex($substr))));
			}
			
			my $z = 0; 	#old bit
			my $v = 0; 	#new bit
			my $time="";#rueckgabestring
			for(my $i=0;$i < length($ret);$i++){
				$v = substr($ret,$i,1)+0;													#bit extrahieren
				$time.= $a[2]."_".substr($days[int($i/96)],0,2).":\t" if($i%96 == 0);		#Wochentag in string
				if($v != $z){																#zeit eintrag bei unterschiedlichen bits
					$z = $v;
					$time.= ( $z == 1 )? sprintf("%02d",int(($i%96)/4)).":".$kms_schaltarray[$i%4]."-" : sprintf("%02d",int(($i%96)/4)).":".$kms_schaltarray[$i%4]." ";
				}
				$time.= "\n" if($i%96 == 95);												#wochentag abschließen
			}
			
			$ret = $time;
		}
		elsif($a[2] eq "Bitstring"){
			for(my $i=0;$i<$length*2;$i++){
				$substr = substr($answer,($i*2)+7,2);
				$ret.= reverse(sprintf("%08d",sprintf("%b",hex($substr))));
				if($i%12==11){
					$ret.="\n";
				}
			}
		}
	}elsif($cmd eq "Status"){
	
		RemoveInternalTimer("pollTimer:".$name);
		$hash->{pollTimeState} = 0;
		$hash->{pollGetState} = 1;
		KMS_pollStatus($hash);
		
	}else {
		return "$name get $cmd unknown command";
	}
	
	if(not defined $attr{$name}{disable} or $attr{$name}{disable} == 0){
		RemoveInternalTimer("pollTimer:".$name);
		InternalTimer(gettimeofday() + $attr{$name}{pollTime}, "KMS_pollTimer", "pollTimer:".$name, 0);
	
		$hash->{pollTimeState} += 1;
		$hash->{pollTimeState} = 1 if $hash->{pollTimeState} > $attr{$name}{pollRunTime};
	}

	return $ret;
}

#####################################
sub KMS_pollStatus($)
{

	my ($hash) = @_;
	my $name = $hash->{NAME};
	my $pollGetState = int($hash->{pollGetState});
	my $pollTimeState = int($hash->{pollTimeState}) % int($attr{$name}{pollRunTime});
	
	if ((not defined $attr{$name}{disable} or $attr{$name}{disable} == 0) || $pollGetState == 1) {
	
		if ($hash->{STATE} eq 'disconnected') {
			RemoveInternalTimer("pollTimer:".$name);
			DevIo_OpenDev($hash, 1, "KMS_DoInit");
			Log3 $name, 4, "$name: Device not connected.";
			return;
		}
		Log3 $name, 4, "$name: poll ReadStatus";
		
		my $head = ":";
		my $foot = "\r\n";
		my $expect = ".*\\r\\n";
		
		my $msg = "";
		
		$msg = $head."80030000003C41".$foot if($pollTimeState != 0 ); # Statusabfrage alle X Sekunden laut Attribut pollTime Register 1-60
		$msg = $head."800301900014D8".$foot if($pollTimeState == 0 ); # Laufzeiten Relais abfrage alle X Sekunden laut Attribut pollRunTime Register 400-420

		
		my $answer = "";
		
		if($attr{$name}{debugModus} == "0"){
			$answer = KMS_SimpleExpect($hash, $msg, $expect);
		}else{
#			DebugAnswers
			$answer = ":80037809271D0B10070001006E0068100000DC00960001005A00E1100200DC0096000200000000100002F4000000010000000000000000000000000000000100000000000000000000009803C100000C2D00F402960167023F016A0C1C0C25003C003CFE0CFE0C00F40276002802440028FE0CFE0C003C003C002894\r\n" if($pollTimeState != 0 );
			$answer = ":8003280000000100010313000000000000031500000000221A000005240003000000000000000000000000AA\r\n" if($pollTimeState == 0 );
		}
		
		my $useHK2 = 1;
		if($attr{$name}{useHK2} == "0"){
			fhem("deletereading $name HK2_.*");
			$useHK2 = 0;
		}

		if(defined($answer)){
			if($answer =~ m/^$expect$/) {
				KMS_WriteKmsArray($hash,$answer);
				
				#readingsBeginUpdate($hash);
				foreach my $kms_value (@kms_array){
					#Neue Readings anlegen
					if(not defined $hash->{READINGS}{@$kms_value[8]}{VAL}){
						#$hash->{READINGS}{@$kms_value[8]}{VAL} = @$kms_value[6];
						#$hash->{READINGS}{@$kms_value[8]}{TIME} = TimeNow();
						readingsSingleUpdate($hash,@$kms_value[8],@$kms_value[6],0) if($useHK2 or (!$useHK2 and @$kms_value[8] !~/^HK2_/));
					}
					#Nur bei geänderten Werten updaten
					if( ($hash->{READINGS}{@$kms_value[8]}{VAL} !~ m/^@$kms_value[6]$/)){
					
						if($attr{$name}{updateTime}=="1"){
							#$hash->{READINGS}{@$kms_value[8]}{VAL} = @$kms_value[6];
							#$hash->{READINGS}{@$kms_value[8]}{TIME} = TimeNow();
							#readingsBulkUpdate($hash,@$kms_value[8],@$kms_value[6]);
							readingsSingleUpdate($hash,@$kms_value[8],@$kms_value[6],1) if($useHK2 or (!$useHK2 and @$kms_value[8] !~/^HK2_/));
						}else{
							if(@$kms_value[8] ne "Datum_Zeit"){
								#$hash->{READINGS}{@$kms_value[8]}{VAL} = @$kms_value[6] ;
								#$hash->{READINGS}{@$kms_value[8]}{TIME} = TimeNow() ;
								#readingsBulkUpdate($hash,@$kms_value[8],@$kms_value[6]) ;
								readingsSingleUpdate($hash,@$kms_value[8],@$kms_value[6],1) if($useHK2 or (!$useHK2 and @$kms_value[8] !~/^HK2_/));
							}else{
								readingsSingleUpdate($hash,@$kms_value[8],@$kms_value[6],0) if($useHK2 or (!$useHK2 and @$kms_value[8] !~/^HK2_/));
							}							
						}
					}
				}
				#readingsEndUpdate($hash, 1);
			}else{
				Log3 $name, 4, "$name: unvollständige Antwort im ReadStatus() empfangen: " . KMS_DebugComment($answer);
			}
		} else {
			Log3 $name, 4, "$name: Keine Antwort im ReadStatus() empfangen";
		}
		
		$hash->{pollGetState} = 0;
		
	} else {
		Log3 $name, 4, "$name: polling disabled.";
	}
	
	
	if($pollTimeState == 0){
		$hash->{pollTimeState} += 1;
		KMS_pollStatus($hash);
	}else{
		if(not defined $attr{$name}{disable} or $attr{$name}{disable} == 0){
			RemoveInternalTimer("pollTimer:".$name);
			InternalTimer(gettimeofday() + $attr{$name}{pollTime}, "KMS_pollTimer", "pollTimer:".$name, 0);
	
			$hash->{pollTimeState} += 1;
			$hash->{pollTimeState} = 1 if $hash->{pollTimeState} > $attr{$name}{pollRunTime};
		}
	}
}

#####################################
sub KMS_pollTimer($)
{
  my $in = shift;
  my (undef,$name) = split(':',$in);
  my $hash = $defs{$name};

  KMS_pollStatus($hash);
}

#####################################
sub KMS_WriteKmsArray($$)
{

	my ($hash,$bs) = @_;
	my $kms_array_length = @kms_array;
	my $kms_array_status_length = 60;
	
	#Setze Startwert und Länge (120 = Statusabfrage = erste 60 Arrayzeilen , danach Betriebsstunden)
	my $a = (hex(substr($bs,5,2)) == 120) ? $kms_array_status_length-$kms_array_status_length : $kms_array_status_length;
	my $l = (hex(substr($bs,5,2)) == 120) ? $kms_array_status_length : $kms_array_length;
	
	for(my $i = $a; $i < $l ; $i++) {
	
		my $t   = "";
		my $hex = substr($bs,$kms_array[$i][0],$kms_array[$i][1]);
		$kms_array[$i][2] = $hex;
		
		#DateTime extrahieren
		if($kms_array[$i][3] eq "z"){
			#				Tag											Monat										Jahr											Stunde										Minute									Sekunde
			$kms_array[$i][6] = sprintf("%02d",hex(substr($hex,4,2))).".".sprintf("%02d",hex(substr($hex,10,2))).".".(sprintf("%02d",hex(substr($hex,8,2)))+2000)." - ".sprintf("%02d",hex(substr($hex,6,2))).":".sprintf("%02d",hex(substr($hex,0,2))).":".sprintf("%02d",hex(substr($hex,2,2)));
		}
		
		#Rückgabe String
		if($kms_array[$i][3] eq "s"){
			#Byte aus Word extrahieren
			if($kms_array[$i][4] eq "b"){
				$t=0;
				$t = hex(substr($hex,length($hex)-($kms_array[$i][5]*2)-2,2));
				if($kms_array[$i][8] =~ m/^HK.*Betriebsart$/) {
					$kms_array[$i][6] = $kms_hk_betriebsarten[$t];
				}
				if($kms_array[$i][8] =~ m/^WW.*Betriebsart$/) {
					$kms_array[$i][6] = $kms_ww_betriebsarten[$t];
				}
				if($kms_array[$i][8] =~ m/^.*Zeitprogramm$/) {
					$kms_array[$i][6] = ( $t > 15 )? $kms_zeitprogramm[$t-16] : $kms_zeitprogramm[$t];
				}
			}
			#Sondermodus liefert 3 Register (Art,Zeit,Temp)
			if($kms_array[$i][4] eq "sm"){
				#Benutzerdefiniertes encoding
				my $r3  = substr($hex,8,4);
				my $r2  = substr($hex,4,4);
				my $r1  = substr($hex,0,4);
				my $str = "";
				
				if($kms_array[$i][8] =~ m/^HK.*Sondermodus$/) {
					$str = $kms_hk_sondermodus[hex($r1)] if( hex($r1)==0 );
					$str = $kms_hk_sondermodus[hex($r1)] ." ". KMS_TimeSpan((hex($r2)*15),1) ." ". sprintf("%.1f", hex($r3) / 10) if( hex($r1)==1 || hex($r1)==2 );
					$str = $kms_hk_sondermodus[hex($r1)] ." ". sprintf("%02d",hex(substr($r2,2,2))) .".". sprintf("%02d",hex(substr($r2,0,2))) .". ". sprintf("%.1f", hex($r3) / 10) if( hex($r1)==3 );
				}
				if($kms_array[$i][8] =~ m/^WW.*Sondermodus$/) {
					$str = $kms_ww_sondermodus[hex($r2)] if( hex($r1)==0 );
					$str = $kms_ww_sondermodus[hex($r2)] if( hex($r1)==1 );
				}
				$kms_array[$i][6] = $str;
			}
		}

		#Rückgabe Float
		if($kms_array[$i][3] eq "f"){
				if($kms_array[$i][4] eq "d"){
					#Decimal dividiert
					
						# 16bit Hex zu signed Int16
						my $signed_int = ( hex($hex) >> 15 ) ? hex($hex) - 2 ** 16 : hex($hex);
						
						# signed_int muss größer -500 und kleiner 3000 sein, sonst ungültig
						$kms_array[$i][6] = ( $signed_int > -500 && $signed_int < 3000) ? sprintf("%.1f", $signed_int / $kms_array[$i][5]) : "- - -";
				}
		}
		
		#Rückgabe Binär
		if($kms_array[$i][3] eq "b"){
				if($kms_array[$i][4] eq "l"){
					#Binärzeichenkette auf volle Bytes
						$kms_array[$i][6] = sprintf("%0".$kms_array[$i][5]."d",sprintf("%b",hex($hex)));
				}
				if($kms_array[$i][4] eq "p"){
					#Einzelnes Bit
						$kms_array[$i][6] = substr(sprintf("%0".($kms_array[$i][1]*4)."d",sprintf("%b",hex($hex))),$kms_array[$i][5],1);
				}
		}
		
		#Rückgabe Zählwert
		if($kms_array[$i][3] eq "zw"){
			$kms_array[$i][6] = hex($hex);
		}
		
	}
}

########################################
# Macht aus 1/4h einheiten volle Uhrzeit
sub KMS_TimeSpan($$){
	my ($time,$op) = @_;
	# Aus virtelstunden Ganzzahl schöne Zeit machen - Return hh:ii
	if($time=~ /^\d+$/ && $op == 1){
		return sprintf("%02d",int($time/60)).":".sprintf("%02d",$time%60);
	}
	# Zeit 19:38 schön machen - Return viertelstunden in hex tttt
	elsif($time=~ /^\d{1,2}:\d{2}$/ && $op == 2){
		my ($h,$i) = split(/:/,$time);
		if($h+0>=0 && $h+0<=23 && $i+0>=0 && $i+0<=59){
			return	sprintf("%04X",(($h*4)+int(($i/15)+0.5)));
		}
	}
	# Zeit +38 schön machen - Return viertelstunden in hex tttt
	elsif($time=~ /^\+\d+$/ && $op == 4){
		my $stamp = ((substr($time,1)+0)*60)+time;
		my ($sec,$i,$h,$mday,$mon,$year,$wday,$yday,$isdst)=localtime($stamp);
		#Log3 "KMS", 3, "KMS TIME NEW ".sprintf("%02d",$h).":".sprintf("%02d",$i);
		return	sprintf("%02d",$h).":".sprintf("%02d",$i);
	}
	# Datum 30.04. schön machen - Return TagMonat in hex ddmm
	elsif($time=~ /^\d{1,2}\.\d{1,2}\.$/ && $op == 3){
		my ($d,$m) = split(/\./,substr($time,0,length($time)-1));
		#Log3 "KMS", 3, "KMS DATE STR: ".$d." - ".$m;
		$d+=0;
		$m+=0;
		#Log3 "KMS", 3, "KMS DATE INT: ".$d." - ".$m;
		if($d > 0 && $d <= 31 && $m > 0 && $m <= 12){
		#Log3 "KMS", 3, "KMS DATE HEX: ".sprintf("%02X",$d).sprintf("%02X",$m);
			return	sprintf("%02X",$m).sprintf("%02X",$d);
		}
	}
	return "-1";
}

#####################################
sub KMS_Reopen($)
{
  my ($hash) = @_;
  DevIo_CloseDev($hash);
  DevIo_OpenDev($hash, 1, undef);

  return undef;
}

#####################################
sub KMS_Set($@)
{
  my ($hash, @a) = @_;
  return "\"set KMS\" needs at least an argument" if(@a < 2);
  my $name = shift @a;

  if(!defined($kms_sets{$a[0]})) {
    my $msg = "";
    foreach my $para (sort keys %kms_sets) {
		if ($attr{$name}{useHK2} == 0 && $para=~/^HK2/){
			$msg .= '';
		}else{
			$msg .= " $para" . $kms_sets{$para}{OPT};
		}
    }
    return "Unknown argument $a[0], choose one of" . $msg;
  }
  
  #Set aus $kms_sets in $cmd schreiben
  my $cmd = $kms_sets{$a[0]}{SET};
  Log3 $name, 5, "$name: set " . $cmd;
  
  #Prüfung wenn Set mit Parameter dann variablen belegen
  my ($val, $numeric_val, $find, $cmd_set, $fehler, $valkey, $valold, @workarray);
  $find = "_VALUE_LRC";
  $cmd_set = 0;
  $fehler = "";
  $valkey  = -1;
  $valold = "";
  
  if($cmd =~ m/_VALUE_LRC$/) {
    return "\"set KMS $a[0]\" needs at least one parameter" if(@a < 2);
    $val = $a[1];
    $numeric_val = ($val =~ m/^[.0-9]+$/);
  }
  
  # 0 Set_Command Reopen
  if($a[0] =~ m/^reopen$/) {
    return KMS_Reopen($hash);
  }
  # 1 Set_Command HK 1/2 Tag/Nacht Soll oder WW_Soll
  elsif($a[0] =~ m/^.*_Soll$/){
	return "Argument must be numeric (between 10 and 30)" if((!$numeric_val || $val < 10 || $val > 30) && $a[0] =~ m/^HK.*Soll$/);
	return "Argument must be numeric (between 30 and 70)" if((!$numeric_val || $val < 30 || $val > 70) && $a[0] =~ m/^WW_Soll$/);
  
	$val = sprintf("%04X",$val*10);
	$cmd_set = 1;
  }
  # 2 Set_Command HK 1/2 Betriebsart oder HK 1/2 Zeitprogramm oder WW Betriebsart oder WW Zeitprogramm
  elsif($a[0] =~ m/^.*_Betriebsart$/ || $a[0] =~ m/^.*_Zeitprogramm$/){
  
	#Bestehenden Wert ermitteln - 4stellig
	for(my $i = 0; $i < @kms_array; $i++) {
		$valold = $kms_array[$i][2] if(lc($a[0]) eq lc($kms_array[$i][8]));
	}
	$valold = "1000" if(length($valold)<4);
 
	@workarray = @kms_hk_betriebsarten if($a[0] =~ m/^HK.*Betriebsart$/);
	@workarray = @kms_ww_betriebsarten if($a[0] =~ m/^WW.*Betriebsart$/);
	@workarray = @kms_zeitprogramm if($a[0] =~ m/^.*_Zeitprogramm$/);

	for(my $i = 0; $i < @workarray; $i++) {
		$fehler .= $workarray[$i]." ";
		$valkey = $i if(lc($workarray[$i]) eq lc($val));
	}
	
	return "Argument must be one of this parameter: $fehler" if($valkey < 0);

	#$val beinhaltet 4 Stellen 2 Zeitprogramm und 2 Betriebsart
	#Betriebsart ersten beiden stehen lassen letzte beiden durch neuen wert ersetzen
	if($a[0] =~ m/^.*_Betriebsart$/){
		$val = substr($valold,0,2).sprintf("%02X",$valkey);
	}
	#Zeitprogramm ersten beiden ersetzen letzte beiden stehen lassen
	elsif($a[0] =~ m/^.*_Zeitprogramm$/){
		$val = sprintf("%02X",$valkey).substr($valold,2,2);
	}
	
	$cmd_set = 2;
  }
  # 3 Sondermodus
  elsif($a[0] =~ m/^.*_Sondermodus$/){
	return "\"set KMS $a[0]\" needs parameter [Aus|Party Time Temp|Eco Time Temp|Urlaub Days Temp]" if(@a < 2 && $a[0] =~ m/^HK.*Sondermodus$/);
	return "\"set KMS $a[0]\" needs parameter [Aus|Warmmachen]" if(@a < 2 && $a[0] =~ m/^WW_Sondermodus$/);

	#Bestehenden Wert ermitteln - 12stellig
	for(my $i = 0; $i < @kms_array; $i++) {
		$valold = $kms_array[$i][2] if(lc($a[0]) eq lc($kms_array[$i][8]));
	}
	$valold = "000000000000" if(length($valold)<12);
	
	@workarray = @kms_hk_sondermodus if($a[0] =~ m/^HK.*Sondermodus$/);
	@workarray = @kms_ww_sondermodus if($a[0] =~ m/^WW_Sondermodus$/);
	
	for(my $i = 0; $i < @workarray; $i++) {
		$fehler .= $workarray[$i]." ";
		$valkey = $i if(lc($workarray[$i]) eq lc($val));
	}
	
	# Kein valkey gefunden, somit Befehl unbekannt
	return "\"set KMS $a[0]\" needs one of this parameter: $fehler" if($valkey < 0);
	# Zeitangabe und oder Temp fehlen
	return "\"set KMS $a[0] $a[1]\" needs Time 19:38 and Temp 17.0 parameter!" if(($valkey == 1 || $valkey == 2) && @a < 4 && $a[0] =~ m/^HK.*Sondermodus$/);
	# Datumsangabe und oder Temp fehlen
	return "\"set KMS $a[0] $a[1]\" needs Date 30.04. and Temp 15.0 parameter!" if($valkey == 3 && @a < 4 && $a[0] =~ m/^HK.*Sondermodus$/);
	# Zeitangabe unbekanntes Format
	return "\"set KMS $a[0] $a[1]\" Time is not readable! Format is hh:ii or +ii" if(($valkey == 1 || $valkey == 2) && $a[0] =~ m/^HK.*Sondermodus$/ && (KMS_TimeSpan($a[2],2) eq "-1" && KMS_TimeSpan($a[2],4) eq "-1"));
	# Datumsangabe unbekanntes Format
	return "\"set KMS $a[0] $a[1]\" Date is not readable! Format is DD.MM." if($valkey == 3 && $a[0] =~ m/^HK.*Sondermodus$/ && KMS_TimeSpan($a[2],3) eq "-1");
	# Temperatur unbekanntes Format
	return "\"set KMS $a[0] $a[1]\" Temp is not readable! Format is 17.0 or 18.5 or 16" if($valkey > 0 && $a[0] =~ m/^HK.*Sondermodus$/ && $a[3] !~ m/^[.0-9]+$/);
	# Temperatur ausserhalb des bereiches
	return "\"set KMS $a[0] $a[1]\" Temp must between 4 and 30!" if($valkey > 0 && $a[0] =~ m/^HK.*Sondermodus$/ && $a[3] < 4 && $a[3] > 30);
	
	
	my $qm = 0;
	
	# HK 1/2 Sondermodus
	if($a[0] =~ m/^HK.*Sondermodus$/){
		#Aus valkey=0
		if($valkey == 0){
			$val = sprintf("%04X",$valkey).substr($valold,4,8);
		}
		#Party valkey=1
		elsif($valkey == 1){
			$qm = ( $a[2] =~ /^\+\d+$/ ) ? KMS_TimeSpan($a[2],4) : $a[2] ;
			$val = sprintf("%04X",$valkey).KMS_TimeSpan($qm,2).sprintf("%04X",int($a[3]*10));
		}
		#Eco valkey=2
		elsif($valkey == 2){
			$qm = ( $a[2] =~ /^\+\d+$/ ) ? KMS_TimeSpan($a[2],4) : $a[2] ;
			$val = sprintf("%04X",$valkey).KMS_TimeSpan($qm,2).sprintf("%04X",int($a[3]*10));
		}
		#Urlaub valkey=3
		elsif($valkey == 3){
			$val = sprintf("%04X",$valkey).KMS_TimeSpan($a[2],3).sprintf("%04X",int($a[3]*10));
		}
	}
	# WW Sondermodus
	elsif($a[0] =~ m/^WW_Sondermodus$/){
		$val = sprintf("%04X",$valkey).substr($valold,4,8);
	}
	
	#Log3 $name, 3, "$name: valold: " . substr($valold,0,4) . " " . substr($valold,4,4) . " " . substr($valold,8,4);
	#Log3 $name, 3, "$name: valnew: " . substr($val,0,4) . " " . substr($val,4,4) . " " . substr($val,8,4);
	
	$cmd_set = 3;
  }

  #Wenn cmd_set > 0 befehl feuern
  if($cmd_set > 0){
	RemoveInternalTimer("pollTimer:".$name);
	
	$cmd =~ s/$find/$val/g;
	$cmd = ":".KMS_LRC($cmd)."\r\n";

	my $expect = ".*\\r\\n";
	my $answer = "";
	
	$answer = KMS_SimpleExpect($hash, $cmd, $expect);
	
	Log3 $name, 3, "$name: set KMS " . join(" ", @a);
	Log3 $name, 4, "$name: $a[0] DeviIO_Write ".KMS_DebugComment($cmd);
	Log3 $name, 4, "$name: $a[0] DeviIO_Read ".KMS_DebugComment($answer);
	
	$cmd_set = 0;
	InternalTimer(gettimeofday() + $attr{$name}{pollTime}, "KMS_pollTimer", "pollTimer:".$name, 0);
  }

  return undef;
}

sub KMS_LRC($)
{
	my $cmd = shift;
	my $ret = 0;
	
	for(my $i=0;$i<length($cmd);$i+=2){
		$ret += hex(substr($cmd,$i,2));
	}
	$ret = $ret * -1;
	my $hexreturn = sprintf("%02X",$ret);
	$ret = substr($hexreturn,length($hexreturn)-2,2);
	
	return $cmd.$ret;
}

#####################################
# called from the global loop, when the select for hash->{FD} reports data
sub KMS_Read($) 
{
  my ($hash) = @_;
  
  return undef;
}

#####################################

1;

=pod
=item helper
=item summary Interface for OEG-KMS/KMS+/KSF-Pro Seltron-KXD Solarbayer-D30 heating controller
=item summary_DE Anbindung für OEG-KMS/KMS+/KSF-Pro Seltron-KXD SolarBayer-D30 Heizungssteuerung
=begin html

<a name="KMS"></a>
<h3>KMS</h3>
<ul>
  KMS is the name of the communication device for the OEG KMS/KMS+/KSF-Pro,
  Seltron KXD or  Solarbayer D30 heating controller. It is connected via a
  USB line to the fhem computer.
  <br><br>

  <a name="KMSdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; KMS &lt;usb-device-name&gt;</code>
    <br><br>
    Example:
    <ul>
      <code>define KMS KMS /dev/ttyACM@9600</code><br>
    </ul>
  </ul>
  <br>

  <a name="KMSset"></a>
  <b>Set</b>
  <ul>
    <code>set KMS &lt;param&gt; [&lt;value&gt; [&lt;values&gt;]]</code><br><br>
    where param is one of:
    <ul>
      <li>HK1_Tag_Soll &lt;temp&gt;<br>
          sets the by day temperature for heating circuit 1<br>
          0.5 celsius resolution - temperature between 10 and 30 celsius</li>
      <li>HK2_Tag_Soll &lt;temp&gt;<br>
          sets the by day temperature for heating circuit 2<br>
          (see above)</li>
      <li>HK1_Nacht_Soll &lt;temp&gt;<br>
          sets the by night temperature for heating circuit 1<br>
          (see above)</li>
      <li>HK2_Nacht_Soll &lt;temp&gt;<br>
          sets the by night temperature for heating circuit 2<br>
          (see above)</li>
      <li>HK1_Betriebsart [Automatik|Tag|Nacht|Aus]<br>
          sets the working mode for heating circuit 1<br>
          <ul>
            <li>Automatik: the timer program is active and the summer configuration is in effect</li>
            <li>Tag: manual by day working mode, no timer program is in effect</li>
            <li>Nacht: manual by night working mode, no timer program is in effect</li>
            <li>Aus: heating circuit off</li>
          </ul></li>
      <li>HK2_Betriebsart [Automatik|Tag|Nacht|Aus]<br>
          sets the working mode for heating circuit 2<br>
          (see above)</li>
      <li>WW_Soll &lt;temp&gt;<br>
          sets the hot water temperature<br>
          1.0 celsius resolution - temperature between 30 and 70 celsius</li>
      <li>WW_Betriebsart [Automatik|Tag|Aus]<br>
          sets the working mode for hot water<br>
          <ul>
            <li>Automatik: hot water production according to the working modes of both heating circuits</li>
            <li>Tag: manual permanent hot water</li>
            <li>Aus: no hot water at all</li>
          </ul></li>
      <li>HK1_Zeitprogramm [1|2]<br>
          sets the timer program for heating circuit 1<br>
          <ul>
            <li>1: the first custom program defined by the user is used</li>
            <li>2: the second custom program defined by the user is used</li>
          </ul></li>
      <li>HK2_Zeitprogramm [1|2]<br>
          sets the timer program for heating circuit 2<br>
          (see above)</li>
      <li>HK1_Sondermodus [&lt;Party&gt; Time Temp|&lt;Eco&gt; Time Temp|&lt;Urlaub&gt; Date Temp|&lt;Aus&gt;]<br>
          sets (or deactivates) a special working mode for the custom program of heating circuit 1<br>
          <ul>
            <li>Party: timed partymode<br>
                valid arguments for time HH:MM or +MM and for temp 0.5 celsius resolution between 10 and 30 celsius</li>
            <li>Eco: timed ecomode<br>
                valid arguments for time HH:MM or +MM and for temp 0.5 celsius resolution between 10 and 30 celsius</li>
            <li>Urlaub: timed holidaymode<br>
                valid arguments for date DD.MM. and for temp 0.5 celsius resolution between 10 and 30 celsius</li>
            <li>Aus: deletes all special working mode of heating circuit 1</li>
          </ul></li>
          <br>
          Example:
          <ul>
            <code>set KMS HK1_Sondermodus Party 23:45 24.0</code><br>
            <code>set KMS HK1_Sondermodus Eco +60 16</code><br>
            <code>set KMS HK1_Sondermodus Urlaub 30.04. 9.0</code><br>
          </ul><br>
      <li>HK2_Sondermodus [&lt;Party&gt; Time Temp|&lt;Eco&gt; Time Temp|&lt;Urlaub&gt; Date Temp|&lt;Aus&gt;]<br>
          sets (or deactivates) a special working mode for the custom program of heating circuit 2<br>
          (see above)</li>
      <li>WW_Sondermodus [&lt;Warmmachen&gt;|&lt;Aus&gt;]<br>
          sets (or deactivates) a special working mode for the custom program of hot water<br>
          <ul>
            <li>Warmmachen: one time heating the hot water to desired temp</li>
            <li>Aus: deletes all special working mode of hot water</li>
          </ul></li>
      <li>ZH_USB_Device_Reopen<br>
          reconnect to device</li>
    </ul>
  </ul>
  <br>

  <a name="KMSget"></a>
  <b>Get</b>
  <ul>
    <code>get KMS &lt;param&gt;</code><br><br>
    where param is one of:
    <ul>
      <li>RAW [ModbusASCIIstring]<br>
          for debug only. send a string and return the register</li>
      <li>Status<br>
          refresh pollTimeState</li>
    </ul>
  </ul>
  <br>

  <a name="KMSattr"></a>
  <b>Attributes</b>
  <ul>
    <li>disable<br>
        polling disabled</li>
    <li>pollTime<br>
        poll controler in seconds</li>
    <li>pollRunTime<br>
        every seconds read the register of heating counts and time</li>
    <li>timeout<br>
        seconds to timeout a querry
        </li>
  </ul>

=end html
=cut
#!/usr/bin/perl -w
#
# GnomeRSVP by Gregory S Hayes <syncomm@icebreaker.net>
#
# This program is designed to improve reading speed with
# a technique known as Rapid Serial Visual Projection
#
# GnomeRSVP Homepage: http://www.icebreaker.net/gnomersvp/
#

use IO::File;
use Glib;
use Gtk2 -init;
use Gtk2::GladeXML;
use Gnome2;
use Gnome2::Canvas;
use Gnome2::GConf;
use Data::Dumper;
use Carp;
use POSIX;
use threads;
use strict;
use warnings;

our $VERSION = '2.0';
our $dataDir = $ENV{HOME} . '/.gnomersvp';
#our $DEBUG = undef;
our $DEBUG = 1;

Gnome2::Program->init('gnomersvp', $VERSION);


our $gladeXMLFile = 'gnomersvp.glade';
our $gladeXML;

{
   local $/;
   my $gladeData = <DATA>;

   if (defined($gladeData) && length($gladeData) > 1) {
      $gladeXML = new_from_buffer Gtk2::GladeXML($gladeData);
   } elsif (-f $gladeXMLFile) {
      $gladeXML = new Gtk2::GladeXML($gladeXMLFile) || croak("Can't read gladeXML: $!");
   } else {
      print STDERR "ERROR: Can't find GladeXML file: $gladeXMLFile\n";
      exit(1);
   }
}

our $gnomeRsvpApp = $gladeXML->get_widget('gnomeRsvp') || croak("Can't find gnomeRsvp widget");

our $textView = $gladeXML->get_widget('textView') || croak("Can't find textView widget");
our $scale = $gladeXML->get_widget('scale') || croak("Can't find scale widget");
our $appbar = $gladeXML->get_widget('appbar')->get_children()->child() || croak("Can't find appbar widget");

our $startButton = $gladeXML->get_widget('startButton')->child() || croak("Can't find startButton widget");
our $stopButton = $gladeXML->get_widget('stopButton')->child() || croak("Can't find stopButton widget");
$stopButton->set_sensitive(0);

our $startMenuItem = $gladeXML->get_widget('startMenuItem') || croak("Can't find startMenuItem widget");
our $stopMenuItem = $gladeXML->get_widget('stopMenuItem') || croak("Can't find stopMenuItem widget");
$stopMenuItem->set_sensitive(0);

our $preferencesDialog = $gladeXML->get_widget('preferencesDialog') || croak("Can't find preferencesDialog widget");

our $variableTimeCheckButton = $gladeXML->get_widget('variableTimeCheckButton') || croak("Can't find variableTimeCheckButton widget");
our $maxPunctuationTimingSpinButton = $gladeXML->get_widget('maxPunctuationTimingSpinButton') || croak("Can't find maxPunctuationTimingSpinButton widget");
our $newParagraphTimingSpinButton = $gladeXML->get_widget('newParagraphTimingSpinButton') || croak("Can't find newParagraphTimingSpinButton widget");
our $averageWordLengthSpinButton = $gladeXML->get_widget('averageWordLengthSpinButton') || croak("Can't find averageWordLengthSpinButton widget");
our $wordGroupSizeSpinButton = $gladeXML->get_widget('wordGroupSizeSpinButton') || croak("Can't find wordGroupSizeSpinButton widget");
our $updateIntervalSpinButton = $gladeXML->get_widget('updateIntervalSpinButton') || croak("Can't find updateIntervalSpinButton widget");
our $speedChangePercentSpinButton = $gladeXML->get_widget('speedChangePercentSpinButton') || croak("Can't find speedChangePercentSpinButton widget");
our $saveBookmarkOnExitCheckButton = $gladeXML->get_widget('saveBookmarkOnExitCheckButton') || croak("Can't find saveBookmarkOnExitCheckButton widget");

our $canvas = $gladeXML->get_widget('rsvpCanvas');
our $newstyle = $canvas->style()->copy;
our $canvasRoot = $canvas->root();

our $running = undef;
our $startHilightIter;
our $endHilightIter;
our $startWordIter;
our $endWordIter;
our $timer;

our $textBuffer;
our $removeTimeout;
our $rsvpCanvasText;
our $c;
our $t;
our $curWord;

our %CONFIG; # Configuration variables should go in here, for now.

our $gconfClient = Gnome2::GConf::Client->get_default();
our $gconfKeyBase = '/apps/gnomersvp';
our %gconfInfo = ($gconfKeyBase . '/maxPunctuationTiming'=>
		  {type=>'float',
		   default=>3,
		   onSet=>sub {
		      $maxPunctuationTimingSpinButton->set_value($_[0]);
		   }
		  },

		  $gconfKeyBase . '/newParagraphTiming'=>
		  {type=>'float',
		   default=>0.75,
		   onSet=>sub {
		      $newParagraphTimingSpinButton->set_value($_[0]);
		   }
		  },

		  $gconfKeyBase . '/averageWordLength'=>
		  {type=>'int',
		   default=>7,
		   onSet=>sub {
		      $averageWordLengthSpinButton->set_value($_[0]);
		   }
		  },

		  $gconfKeyBase . '/updateSpeedInterval'=>
		  {type=>'int',
		   default=>3,
		   onSet=>sub {
		      $updateIntervalSpinButton->set_value($_[0]);
		   }
		  },

		  $gconfKeyBase . '/wordGroupSize'=>
		  {type=>'int',
		   default=>7,
		   onSet=>sub {
		      $wordGroupSizeSpinButton->set_value($_[0]);
		   }
		  },

		  $gconfKeyBase . '/speedChangePercentage'=> 
		  {type=>'int',
		   default=>10,
		   onSet=>sub {
		      $speedChangePercentSpinButton->set_value($_[0]);
		   }
		  },

		  $gconfKeyBase . '/variableTime'=>
		  {type=>'bool',
		   default=>1,
		   onSet=>sub {
		      $variableTimeCheckButton->set_active($_[0]);
		      if ($CONFIG{variableTime}) {
			 $newParagraphTimingSpinButton->set_sensitive(1);
			 $maxPunctuationTimingSpinButton->set_sensitive(1);
			 $averageWordLengthSpinButton->set_sensitive(1);
		      } else {
			 $newParagraphTimingSpinButton->set_sensitive(0);
			 $maxPunctuationTimingSpinButton->set_sensitive(0);
			 $averageWordLengthSpinButton->set_sensitive(0);
		      }
		   }
		  },

		  $gconfKeyBase . '/rsvpFont'=> 
		  {type=>'string',
		   default=>'Sans 36',
		   onSet=>\&changeRsvpFont
		  },

		  $gconfKeyBase . '/speed'=> 
		  {type=>'int',
		   default=>125,
		   onInit=>\&setSpeed
		  },
		  $gconfKeyBase . '/hilightColor'=>
		  {type=>'string',
		   default=>'#FFFF00',
		   onSet=>sub {
		      changeHilightColor(Gtk2::Gdk::Color->parse($CONFIG{hilightColor}));
		   }
		  },
		  $gconfKeyBase . '/rsvpFontColor'=>
		  {type=>'string',
		   default=>'#000000',
		   onSet=>sub {
		      changeRsvpFontColor(Gtk2::Gdk::Color->parse($CONFIG{rsvpFontColor}));
		   }
		  },
		  $gconfKeyBase . '/rsvpBackgroundColor'=>
		  {type=>'string',
		   default=>'#FFFFFF',
		   onSet=>sub{
		      changeRsvpBackgroundColor(Gtk2::Gdk::Color->parse($CONFIG{rsvpBackgroundColor}));
		   }
		  },
		  $gconfKeyBase . '/file'=>{type=>'string', default=>''},
		  $gconfKeyBase . '/position'=>{type=>'int', default=>-1},
		  $gconfKeyBase . '/saveBookmarkOnExit'=>
		  {type=>'bool', default=>1,
		   onSet=>sub {$saveBookmarkOnExitCheckButton->set_active($_[0]);}
		  },
		 );

setupGConf();
$gconfClient->add_dir($gconfKeyBase, 'preload-none');

$variableTimeCheckButton->signal_connect(toggled=>sub {
					    $CONFIG{variableTime} = $_[0]->get_active() ? 1 : 0;
					    if ($CONFIG{variableTime}) {
					       $newParagraphTimingSpinButton->set_sensitive(1);
					       $maxPunctuationTimingSpinButton->set_sensitive(1);
					       $averageWordLengthSpinButton->set_sensitive(1);
					    } else {
					       $newParagraphTimingSpinButton->set_sensitive(0);
					       $maxPunctuationTimingSpinButton->set_sensitive(0);
					       $averageWordLengthSpinButton->set_sensitive(0);
					    }
					    storeConfig('variableTime')});

$saveBookmarkOnExitCheckButton->signal_connect(toggled=>sub {
						  $CONFIG{saveBookmarkOnExit} = $_[0]->get_active() ? 1 : 0;
						  storeConfig('saveBookmarkOnExit');
					       });

$preferencesDialog->signal_connect(response=>sub {$_[0]->hide_all()});

$maxPunctuationTimingSpinButton->signal_connect('value-changed'=>sub {storeConfig('maxPunctuationTiming', $_[0]->get_value())});
$newParagraphTimingSpinButton->signal_connect('value-changed'=>sub {storeConfig('newParagraphTiming', $_[0]->get_value())});
$averageWordLengthSpinButton->signal_connect('value-changed'=>sub {storeConfig('averageWordLength', $_[0]->get_value())});
$wordGroupSizeSpinButton->signal_connect('value-changed'=>sub {storeConfig('wordGroupSize', $_[0]->get_value())});
$updateIntervalSpinButton->signal_connect('value-changed'=>sub {storeConfig('updateSpeedInterval', $_[0]->get_value())});
$speedChangePercentSpinButton->signal_connect('value-changed'=>sub {storeConfig('speedChangePercentage', $_[0]->get_value())});


###############################################################################
#Global configuration variables

# Need to do some research on the best values for these timing options
# A GUI to edit this would be nice.

$CONFIG{PunctuationTiming} = {'...'=>1.0,
			      '..'=>1.0,
			      '!!!'=>1.0,
			      '!!'=>1.0,
			      '???'=>1.0,
			      '??'=>1.0,
			      '.'=>0.75,
			      '!'=>0.75,
			      '?'=>0.75,
			      ';'=>0.50,
			      '--'=>0.50, # Don't know what to set this to now that it is treated as it's own word
			      ':'=>0.25,
			      '"'=>0.25,
			      "''"=>0.25,
			      '``'=>0.25,
			      "'"=>0.25,
			      ' '=>0.10,
			      ''=>0.5}; # Default
$CONFIG{PunctuationTimingRE} = qr/(\.\.+|!!+|\?\?+|--+|\'\'|\`\`|[\.\!\?\"\:\;\'\`\,\@\#\$\%\^\&\*\[\{\]\}\(\)\~\_\-\+\\\|\ ])/;

# End configuration variables
###############################################################################

drawRsvpBackground();
stopRsvp();

$textView->set_wrap_mode('GTK_WRAP_WORD');

if (defined($ARGV[0])) {
   openFile($ARGV[0]);

   if (defined($ARGV[1])) {
      gotoOffset(int($ARGV[1]));
   } else {
      gotoOffset(0);
   }
} elsif (defined($CONFIG{file}) && $CONFIG{file} ne '') {
   load();
}

$gladeXML->signal_autoconnect_from_package('main');
Gtk2->main();

exit;


sub readTextFromFile {
   my ($file) = @_;

   my $text;
   if ($file =~ /\.pdf$/i) {
      open(FH, "pdftotext \"$file\" - |") || croak("Can't launch pdftotext: $!");;
      local $/;
      $text = <FH>;
      close(FH);
   } elsif ($file =~ /^(https?|ftp|gopher|wais|nntp):\/\// || $file =~ /\.html?$/i) {
      open(FH, "lynx -dump -preparsed -accept_all_cookies \"$file\" |") || croak("Can't launch lynx: $!");
      local $/;
      $text = <FH>;
      close(FH);
   } else {
      my $fh = new IO::File($file, 'r') || croak("Can't open file for reading: $file: $!");
      local $/;
      $text = <$fh>;
   }

   $CONFIG{file} = $file;
   $CONFIG{positon} = -1;

   return setupTextBuffer($text);
}


sub pasteToBuffer {
   my $clipboard = Gtk2::Clipboard->get(Gtk2::Gdk->SELECTION_CLIPBOARD);
   my $text = $clipboard->wait_for_text();

   $CONFIG{file} = '';
   $CONFIG{positon} = -1;

   $endWordIter = undef;
   $startWordIter = undef;
   $curWord = undef;
   $startHilightIter = undef;
   $endHilightIter = undef;

   return setupTextBuffer($text);
}


sub setupTextBuffer {
   my ($text) = @_;

   $textBuffer = new Gtk2::TextBuffer();

   my $re = '(?<!\-)\-\-(?!\-)'; # Stupid cperl higlighting

   $text =~ s/\r\n/\n/gm;
   $text =~ s/$re/ -- /gm;
   $text =~ s/\n(?![\n\t])/ /gm;
   $text =~ s/^\s+//gm;
   $text =~ s/\n/\n\n/gm;
   $text =~ s/(?!\n)\s(?!\n)\s+/ /gm;

   print 'Read size: ' . length($text) . "\n" if defined($DEBUG);
   $textBuffer->set_text($text);

   $endWordIter = undef;
   $startWordIter = undef;
   $curWord = undef;
   $startHilightIter = undef;
   $endHilightIter = undef;

   makeHilightTag();
   $textView->set_buffer($textBuffer);

   return $textBuffer;
}


sub toggleRsvp {
   if (defined($running)) {
      stopRsvp();
   } else {
      startRsvp();
   }
}


sub startRsvp {
   return unless defined($textBuffer);

   if (! defined($endWordIter) || $endWordIter->is_end()) {
      if (defined($textBuffer)) {
	 $endWordIter = $textBuffer->get_start_iter() || croak("Can't make iter");
      } else {
	 return;
      }
   }

   $startButton->set_sensitive(0);
   $startMenuItem->set_sensitive(0);

   $running = 1;
   $removeTimeout = undef;
   $appbar->set_label('Reading...');	

   $stopButton->set_sensitive(1);
   $stopMenuItem->set_sensitive(1);
   doRsvp();
}


sub stopRsvp {
   $stopButton->set_sensitive(0);
   $stopMenuItem->set_sensitive(0);

   $running = undef;
   $c = 0;
   $t = undef;

   $startButton->set_sensitive(1);
   $startMenuItem->set_sensitive(1);
}


sub doRsvp {
   # Catch any strays
   if (defined($timer) && defined($removeTimeout) && $timer <= $removeTimeout) {
      print "Removed stray timer\n" if defined($DEBUG);
      return undef;
   }

   $removeTimeout = $timer;

   my ($word, $wao, $endPara) = getNextWord();
   showWord($word);
   hilightWord();

   if (defined($running)) {
      my $time;

      if (defined($CONFIG{variableTime}) && $CONFIG{variableTime}) {
	 $time = calcTimeForWord($word, $wao, $endPara);
      } else {
	 $time = $scale->get_adjustment()->value();
      }

      $timer = Glib::Timeout->add($time, \&doRsvp);

      $c += $wao;
      $t = time() unless defined($t);

      if ($CONFIG{updateSpeedInterval} != 0 && (time()-$t) >= $CONFIG{updateSpeedInterval}) {
	 $appbar->set_label('Reading at ' . int($c/((time()-$t)/60)) . ' words/min.');	
	 $c = 0;
	 $t = time();
      }
   }

   return undef; # This is so the existing timer will end
}


sub getNextWord {
   my $endPara;
   my $wao = 1;
   my $prevWordEndIter;
   my $bail;

   $startWordIter = $endWordIter->copy();

   $endWordIter->forward_word_end() || stopRsvp();
   while (!defined($bail) && !$endWordIter->is_end()) {
      my $prevCharIter = $endWordIter->copy();
      $prevCharIter->backward_char();

      my $nextCharIter = $endWordIter->copy();
      $nextCharIter->forward_char();

      if ($endWordIter->get_char() =~ /^\S$/ && $prevCharIter->get_char() =~ /^\s$/) {
	 my $text = $startWordIter->get_text($endWordIter);

	 $text =~ s/^\s+//m;
	 $text =~ s/\s+/ /gm;

	 if (length($text) <= $CONFIG{wordGroupSize}) {
	    if ($endWordIter->inside_sentence()) {
	       $prevWordEndIter = $prevCharIter->copy();
	       $wao++;
	    }
	 } else {
	    $bail = 1;
	    $nextCharIter->backward_char();
	 }
      } elsif ($endWordIter->ends_sentence()) {
	 $bail = 1;
	 while ($endWordIter->ends_sentence() && $endWordIter->forward_char()) {
	    1;
	 }
	 $nextCharIter->backward_char();

	 if (! $endWordIter->is_end()) {
	    $endPara = 1 if $nextCharIter->get_char() eq "\n";
	 }
      }

      $endWordIter = $nextCharIter;
   }

   my $word = $startWordIter->get_text($endWordIter);

   $word =~ s/^\s+//m;
   $word =~ s/\s+$//m;
   $word =~ s/\s+/ /mg;

   if (length($word) > $CONFIG{wordGroupSize} && defined($prevWordEndIter)) {
      $wao--;
      $endWordIter = $prevWordEndIter;

      $word = $startWordIter->get_text($endWordIter);

      $word =~ s/^\s+//m;
      $word =~ s/\s+$//m;
      $word =~ s/\s+/ /mg;
   }

   stopRsvp() if $endWordIter->is_end();

   return ($word, $wao, $endPara);
}


sub showWord {
   my ($word) = @_;

   #print "Showing: $word\n";

   $rsvpCanvasText->destroy() if defined($rsvpCanvasText);
   $rsvpCanvasText = Gnome2::Canvas::Item->new($canvasRoot, 'Gnome2::Canvas::Text',
					       'x'=>50,
					       'y'=>50,
					       text=>$word,
					       anchor=>'center',
					       font=>$CONFIG{rsvpFont},
					       fill_color_gdk=>$CONFIG{rsvpFontColorObj}
					      );
   $canvas->update_now();

   $curWord = $word;
}


sub hilightWord {
   $textBuffer->remove_tag_by_name('hilight', $startHilightIter, $endHilightIter) if defined($endHilightIter);

   $startHilightIter = $startWordIter->copy();
   $endHilightIter = $endWordIter->copy();

   $textBuffer->apply_tag_by_name('hilight', $startHilightIter, $endHilightIter);
   $textView->scroll_to_iter($endWordIter, 0, 0, 0, 0);

   $appbar->set_label(sprintf('*Stopped*  Position: %d (%d%%)', $startWordIter->get_offset(), 100*$startWordIter->get_offset()/$textBuffer->get_end_iter()->get_offset())) unless defined($running);
}


sub calcTimeForWord {
   my ($text, $wao, $endPara) = @_;

   my $newTime;
   my $re = $CONFIG{PunctuationTimingRE};

   my $value = $scale->get_adjustment()->value();
   my $modify = 0;

   my $workText = $text;

   $modify = ((length($text) - ($CONFIG{averageWordLength}*$wao)) *
	      ($value)) / ($CONFIG{averageWordLength}*$wao);

   $modify = 0 if $modify < 0;

   $value += $modify;
   $modify = 0;

   while ($workText =~ s/$re//) {
      if (defined($1) && $1 ne '') {
	 $modify += $CONFIG{PunctuationTiming}->{$1} || $CONFIG{PunctuationTiming}->{''};
      }
   }

   $modify = $CONFIG{maxPunctuationTiming} if $modify > $CONFIG{maxPunctuationTiming};

   $modify += $CONFIG{newParagraphTiming} if defined($endPara);

   $value += $modify * $value;
   $newTime += $value;

   $newTime = 10 if $newTime < 10;

   #print "Time: $newTime\n";
   return $newTime;
}


sub scaleChanged {
   print "Scale change\n" if defined($DEBUG);
   my $speed = $scale->get_adjustment()->value();

   if ($CONFIG{speed} != $speed) {
      $CONFIG{speed} = $speed;
      storeConfig('speed');
   }
}


sub slower {
   my $value = $scale->get_adjustment()->value();
   my $newValue = int((1+($CONFIG{speedChangePercentage}/100)) * $value);

   $newValue++ if $value == $newValue;

   $scale->get_adjustment()->set_value($newValue);
   scaleChanged();
}


sub faster {
   my $value = $scale->get_adjustment()->value();
   my $newValue = int((1-($CONFIG{speedChangePercentage}/100)) * $value);

   $scale->get_adjustment()->set_value($newValue);
   scaleChanged();
}


sub setSpeed {
   my ($newValue) = @_;

   $scale->get_adjustment()->set_value($newValue);
   scaleChanged();
}


sub previousWord {
   if (! defined($running)) {
      $startWordIter = $textBuffer->get_start_iter() unless defined($startWordIter);
      $endWordIter = $startWordIter->copy();

      while ($startWordIter->backward_char() && ! $startWordIter->starts_word()) {
	 1;
      }

      my $word = $startWordIter->get_text($endWordIter);
      $word =~ s/^\s+//m;
      $word =~ s/\s+$//m;
      $word =~ s/\s+/ /mg;

      showWord($word);
      hilightWord();
   }
}


sub nextWord {
   if (! defined($running)) {
      $endWordIter = $textBuffer->get_start_iter() unless defined($endWordIter);
      $startWordIter = $endWordIter->copy();

      my ($word) = getNextWord();

      showWord($word);
      hilightWord();
   }
}


sub showAboutDialog {
   my $aboutDialog = new Gnome2::About('GnomeRSVP',
				       $VERSION,
				       'Copyright 2004 Gregory S. Hayes and Andrew Phillips',
				       'Rock.',
				       ['Gregory S. Hayes', 'Andrew Phillips']);

   $aboutDialog->show();
}


sub showRsvpFontDialog {
   my $rsvpFontDialog = new Gtk2::FontSelectionDialog('RSVP Font');
   $rsvpFontDialog->set_font_name($CONFIG{rsvpFont});
   $rsvpFontDialog->signal_connect(response=>sub {
				      my ($self, $response) = @_;
				      changeRsvpFont($self->get_font_name()) if $response eq 'ok';
				      storeConfig('rsvpFont');
				      $self->destroy();
				   });
   $rsvpFontDialog->show();
}


sub changeRsvpFont {
   my ($font) = @_;
   if (defined($font)) {
      $CONFIG{rsvpFont} = $font;

      if (defined($curWord)) {
	 showWord($curWord);
      }
   }
}


sub showRsvpFontColorDialog {
   my $rsvpFontColorDialog = new Gtk2::ColorSelectionDialog('RSVP Font Color');
   $rsvpFontColorDialog->colorsel()->set_current_color($CONFIG{rsvpFontColorObj});
   $rsvpFontColorDialog->colorsel()->set_has_palette(1);
   $rsvpFontColorDialog->signal_connect(response=>sub {
					   my ($self, $response) = @_;
					   changeRsvpFontColor($self->colorsel()->get_current_color()) if $response eq 'ok';
					   storeConfig('rsvpFontColor');
					   $self->destroy();
					});
   $rsvpFontColorDialog->show();
}


sub changeRsvpFontColor {
   my ($color) = @_;
   if (defined($color)) {
      $CONFIG{rsvpFontColorObj} = $color;
      $CONFIG{rsvpFontColor} = formatColor($color);
      showWord($curWord) if defined($curWord);
   }
}


sub showRsvpBackgroundColorDialog {
   my $rsvpBackgroundColorDialog = new Gtk2::ColorSelectionDialog('RSVP Background Color');
   $rsvpBackgroundColorDialog->colorsel()->set_current_color($CONFIG{rsvpBackgroundColorObj});
   $rsvpBackgroundColorDialog->colorsel()->set_has_palette(1);
   $rsvpBackgroundColorDialog->signal_connect(response=>sub {
						 my ($self, $response) = @_;
						 changeRsvpBackgroundColor($self->colorsel()->get_current_color()) if $response eq 'ok';
						 storeConfig('rsvpBackgroundColor');
						 $self->destroy();
					      });
   $rsvpBackgroundColorDialog->show();
}


sub changeRsvpBackgroundColor {
   my ($color) = @_;

   if (defined($color)) {
      $CONFIG{rsvpBackgroundColorObj} = $color;
      $CONFIG{rsvpBackgroundColor} = formatColor($color);
      drawRsvpBackground();

      showWord($curWord) if defined($curWord);
   }
}


sub drawRsvpBackground {
   $canvas->modify_bg('normal', $CONFIG{rsvpBackgroundColorObj});
}


sub showHilightColorDialog {
   my $hilightColorDialog = new Gtk2::ColorSelectionDialog('Hilight Color');
   $hilightColorDialog->colorsel()->set_current_color($CONFIG{hilightColorObj});
   $hilightColorDialog->colorsel()->set_has_palette(1);
   $hilightColorDialog->signal_connect(response=>sub {
					  my ($self, $response) = @_;
					  changeHilightColor($self->colorsel()->get_current_color()) if $response eq 'ok';
					  storeConfig('hilightColor');
					  $self->destroy();
				       });
   $hilightColorDialog->show();
}


sub changeHilightColor {
   my ($color) = @_;
   if (defined($color)) {
      $CONFIG{hilightColorObj} = $color;
      $CONFIG{hilightColor} = formatColor($color);
      makeHilightTag();
   }
}


sub makeHilightTag {
   return unless defined($textBuffer);

   my $tagTable = $textBuffer->get_tag_table();
   my $tag = $tagTable->lookup('hilight');

   if (defined($tag) && $tag ne '') { # Don't know why it is '' if not found
      $tag->set_property(background_gdk=>$CONFIG{hilightColorObj});
   } else {
      $textBuffer->create_tag('hilight', background_gdk=>$CONFIG{hilightColorObj});
   }
}


sub showOpenFileDialog {
   my $openFileDialog = new Gtk2::FileSelection('Open File');

   $openFileDialog->signal_connect(response=>sub {
				      my ($self, $response) = @_;
				      openFile($self->get_selections()) if $response eq 'ok';
				      $self->destroy();
				   });
   $openFileDialog->show();

}


sub showOpenUrlDialog {
   my $openUrlDialog = new Gtk2::Dialog('Goto URL',
					$gnomeRsvpApp,
					'destroy-with-parent',
					'gtk-cancel'=>'reject',
					'gtk-ok'=>'ok',);
   my $hbox = new Gtk2::HBox();
   $hbox->pack_start(new Gtk2::Label('Open URL'), 0, 0, 0);

   my $openUrlEntry = new Gtk2::Entry();
   $hbox->pack_start($openUrlEntry, 1, 1, 0);

   $openUrlDialog->vbox()->pack_start($hbox, 0, 0, 0);
   $openUrlDialog->signal_connect(response=>sub {
				     my ($self, $response) = @_;
				     openFile($openUrlEntry->get_text()) if $response eq 'ok';
				     $self->destroy();
				  });

   $openUrlDialog->show_all();
}


sub openFile {
   my ($file) = @_;

   $endWordIter = undef;
   $startWordIter = undef;
   $curWord = undef;
   $startHilightIter = undef;
   $endHilightIter = undef;

   readTextFromFile($file);
   gotoOffset(0);
}


sub showGotoOffsetDialog {
   my $offsetDialog = new Gtk2::Dialog('Goto Offset',
				       $gnomeRsvpApp,
				       'destroy-with-parent',
				       'gtk-cancel'=>'reject',
				       'gtk-ok'=>'ok',);
   my $hbox = new Gtk2::HBox();
   $hbox->pack_start(new Gtk2::Label('Offset'), 0, 0, 0);

   my $offsetSpinButton = new_with_range Gtk2::SpinButton(0, 2199023300000, 1);
   $hbox->pack_start($offsetSpinButton, 1, 1, 0);

   $offsetDialog->vbox()->pack_start($hbox, 0, 0, 0);
   $offsetDialog->signal_connect(response=>sub {
				    my ($self, $response) = @_;
				    gotoOffset($offsetSpinButton->get_value_as_int()) if $response eq 'ok';
				    $self->destroy();
				 });

   $offsetDialog->show_all();
}


sub gotoOffset {
   my ($offset) = @_;

   stopRsvp();

   if (defined($textBuffer)) {
      print "New offset: $offset\n" if defined($DEBUG);
      $endWordIter = $textBuffer->get_start_iter();
      $endWordIter->set_offset($offset);

      $timer = undef;
      doRsvp();
      #my ($word) = getNextWord();

      #showWord($word);
      #hilightWord();
   }
}


sub quit {
   save() if defined($CONFIG{saveBookmarkOnExit}) && $CONFIG{saveBookmarkOnExit};

   Gtk2->main_quit();
}


sub setupGConf {
   foreach my $key (sort(keys(%gconfInfo))) {
      my $info = $gconfInfo{$key};
      my $type = $info->{type} || 'string';

      my $var = $key;
      $var =~ s/$gconfKeyBase\/+//;

      my $entry = $gconfClient->get_entry($key, 'C', 0);
      my $val = $entry->{value}->{value};

      if (!defined($val) || $entry->{value}->{type} ne $type) {
	 $val = $info->{default};

	 storeGConf($key, $val, $info);
      }

      $CONFIG{$var} = $val;
      print "INIT: $var = '$CONFIG{$var}' ($type)\n" if defined($DEBUG);
      if (defined($info->{onInit})) {
	 $info->{onInit}($val);
      }

      if (defined($info->{onSet})) {
	 $info->{onSet}($val);
      }
   }

   $gconfClient->notify_add($gconfKeyBase, \&handleGconfNotify);
}


sub storeConfig {
   my ($name, $value) = @_;

   my $key = $gconfKeyBase . '/' . $name;
   my $info = $gconfInfo{$key};

   if (defined($info)) {
      $CONFIG{$name} = $value if defined($value);
      storeGConf($key, defined($value) ? $value : $CONFIG{$name}, $info);
   } else {
      print STDERR "Can't store config variable $key in gconf\n";
   }
}


sub storeGConf {
   my ($key, $val, $info) = @_;

   my $type = $info->{type} || 'string';

   print "SET: $key = '$val' ($type)\n" if defined($DEBUG);

   $gconfClient->set($key,{type=>$type,
			   value=>$val});
}


sub handleGconfNotify {
   my ($client, $cnxn_id, $entry) = @_;

   # Make sure the preference has a valid value
   my $key = $entry->{key};
   my $info = $gconfInfo{$key};

   my $type = $info->{type} || 'string';
   if ($entry->{value}->{type} eq $type) {
      my $var = $key;
      $var =~ s/$gconfKeyBase\/+//;

      if ($CONFIG{$var} ne $entry->{value}->{value}) {
	 $CONFIG{$var} = $entry->{value}->{value};

	 print "NOTIFY: $key = '$CONFIG{$var}' ($type)\n" if defined($DEBUG);
	 $info->{onSet}($CONFIG{$var}) if defined($info->{onSet});
      }
   }
}


sub formatColor {
   my ($color) = @_;

   return sprintf('#%04X%04X%04X', $color->red(), $color->green(), $color->blue()) if defined($color);
}


sub showPreferencesDialog {
   $preferencesDialog->show_all();
}


sub load {
   if (defined($CONFIG{file}) && $CONFIG{file} ne '' && -f $CONFIG{file}) {
      openFile($CONFIG{file});

      if (defined($CONFIG{position}) && $CONFIG{position} > 0) {
	 gotoOffset($CONFIG{position});
      }
   }
}


sub save {
   if (!defined($CONFIG{file}) || $CONFIG{file} eq '') {
      if (! -d $dataDir) {
	 mkdir($dataDir) || croak("Can't create data directory: $dataDir: $!");
      }

      my $file = File::Spec->catfile($dataDir, 'buffer.txt');

      my $fh = new IO::File($file, 'w') || croak("Can't open file for writing");
      print $fh $textBuffer->get_text();
      $fh->close();

      $CONFIG{file} = $file;
   }

   storeConfig('file');

   if (defined($startWordIter)) {
      $CONFIG{position} = $startWordIter->get_offset();
      storeConfig('position');
   }
}

1;


__DATA__

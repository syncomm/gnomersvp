#!/usr/bin/perl -w
#
# GnomeRSVP by Gregory S Hayes <syncomm@icebreaker.net>
#
# This program is designed to improve reading speed with
# a technique known as Rapid Serial Visual Projection
#
# GnomeRSVP Homepage: http://www.icebreaker.net/gnomersvp/
#
use Gtk;
use Gtk::GladeXML;
use Data::Dumper;
use POSIX;

eval {
	require Gnome;
	init Gnome('GnomeRSVP', '1.4');
};
init Gtk if $@;
Gtk::GladeXML->init;

# $glade = new Gtk::GladeXML("gnomersvp.glade");
$glade = new_from_memory Gtk::GladeXML(join("",<DATA>));

$glade->signal_autoconnect_from_package('main');

# Maybe we can grab the app to set the titlebar someday
# when I am not lazy
$app = $glade->get_widget('app1');

# Grab the aboutbox into a Global scalar
# and set the close method to hide the
# widget rather than destroy it
$aboutbox = $glade->get_widget('about2');
$aboutbox->close_hides;

# Get our trusty fileselection widget
$fileselection = $glade->get_widget('fileselection');

# Useful Goto Dialog and components
$goto_dialog = $glade->get_widget('dialog1');
$word_number_entry = $glade->get_widget('word_number_entry');
$wordentry = $glade->get_widget('wordentry');
$current_word_lable = $glade->get_widget('current_word_lable');
$total_word_lable = $glade->get_widget('total_word_lable');

# URL Entry Dialog
$urldialog = $glade->get_widget('urldialog');
$urlentry = $glade->get_widget('urlentry');

# Color Selector
$colordialog = $glade->get_widget('color_dialog');
$colorpicker1 = $glade->get_widget('colorpicker1');
$colormap = $app->get_colormap();
$FONT_COLOR = Gtk::Gdk::Color->parse_color("steelblue");
$FONT_COLOR = $colormap->color_alloc( $FONT_COLOR );
$colorpicker1->set_d( (17990.0/65535.0),
	(33410.0/65535.0),
	(46260.0/65535.0),
	1.0 );

# Get font selection and set default font
$fontselection = $glade->get_widget('fontselection');
$font = '-adobe-helvetica-medium-r-normal--24-*-72-72-p-*-iso8859-1';

# Get textbox and it's scrolled window
# then turn off the editable flag
$scrolled_window = $glade->get_widget('scrolledwindow2');
$textbox = $glade->get_widget('etext');
$textbox->set_editable(0);

# Mmmm... Canvas
$canvas = $glade->get_widget('canvas2');

$newstyle = $canvas->style->copy;
$newstyle->bg('normal', $canvas->style->black);
$canvas->set_style($newstyle);
$canvas_root = $canvas->root;
$canvas_group =  $canvas_root->new($canvas_root, "Gnome::CanvasGroup");

# Control the text scrolling
$scrollbutton = $glade->get_widget('scrollcheck');
$TEXT_SCROLL = 1;

# Get textbox toggle
$textbox_toggle = $glade->get_widget('textboxcheck');

# Location Memory Toggle
$location_toggle = $glade->get_widget('location_toggle');

# Scale looks usefull
$scale = $glade->get_widget('speedscale');

# Get the appbar to set status updates. How do you
# set the appbar for activity mode
$appbar = $glade->get_widget('appbar1');

# Create initial timer. It is set to 300 to reflect the default
# value of $scale->get_adjustment->value
$timer = Gtk->timeout_add( 300, \&display_update, NULL );

# Default the index word to 0
$WORD_INDEX = 0;

# GO off by default
$GO_CLICKED = 0;

# Set total lines read to 0
$TOTAL_LINES = 0;

# Look for config info
$HOME = $ENV{HOME};
if (-e "$HOME/.gnomersvprc") {
	print "Found File\n";
	open (CONFIG, "$HOME/.gnomersvprc");
	while (<CONFIG>) {
		if (/(.*)\t(.*)/) {
			if ($1 eq "FONT") {
				$font = $2;
			} elsif ($1 eq "TEXT_SCROLL" && $2 == 0) {
				$scrollbutton->set_active(0);
			} elsif ($1 eq "TEXTBOX" && $2 == 0) {
				$textbox_toggle->set_active(0);
			} elsif ($1 eq "SPEED") {
				my Gtk::Adjustment($adj) = $scale->get_adjustment;
			        $adj->set_value($2);
        			$scale->set_adjustment( $adj );
        			scale_changed();
			} elsif ($1 eq "FONT_COLOR") {
				my ($red,$green,$blue) = split(":",$2);	
				$FONT_COLOR->{ 'red' } = $red;
        			$FONT_COLOR->{ 'green' } = $green;
        			$FONT_COLOR->{ 'blue' } = $blue;
        			$FONT_COLOR = $colormap->color_alloc( $FONT_COLOR );
				$colorpicker1->set_d( ($red/65535.0),
        			($green/65535.0),
        			($blue/65535.0),
        			1.0 );
			} elsif ($1 eq "LOCATION" && !defined $ARGV[0]) {
				my ($file, $pos) = split(":",$2);
				$TOTAL_LINES = build_word_index($file);
				$WORD_INDEX = $pos;
				display_word();
			} elsif ($1 eq "LTOGGLE" && $2 == 0) {
				$location_toggle->set_active(0);
			}				
		}	
	}
	close CONFIG;
}

# Process the args
if (defined $ARGV[0]) {
	$TOTAL_LINES = build_word_index($ARGV[0]);	
}

main Gtk;

##
# Generic Callbacks...
##
sub gtk_main_quit {
        print "Gnome RSVP exiting...\n";
	print "Saving Session...\n";
	gnomersvp_save_session();
        main_quit Gtk;
}

sub gtk_widget_hide {
	my ($w) = shift;
        $w->hide();
	return 1;
}

sub gtk_widget_show {
        my ($w) = shift;
        $w->show;
}

##
# Menubar Callbacks
##
sub on_about1_activate {
	gtk_widget_show($aboutbox);
}

sub on_open1_activate {
	gtk_widget_show($fileselection);
}

sub on_preferences_activate {
	gtk_widget_show($fontselection);
}

sub on_goto_word_activate {
	$current_word_lable->set_text($WORD_INDEX);
	if (exists $WORD_LIST[1]{'word'}) {
		$total_word_lable->set_text($#WORD_LIST);
	}
	gtk_widget_show($goto_dialog);
}

sub on_select_font_color_activate {
	gtk_widget_show($colordialog);
}

sub on_scrollcheck_activate {
	if ($scrollbutton->active) {
		$TEXT_SCROLL = 1;
	} else {
		$TEXT_SCROLL = 0;
	}
}

sub on_location_toggle_activate {
	if ($location_toggle->active) {
		$LTOGGLE = 1;
	} else {
		$LTOGGLE = 0;
	}
}

sub on_textbox_toggle_activate {
	if ($textbox_toggle->active) {
		gtk_widget_show($scrolled_window);
		$app->set_usize(600,450);
	} else {
		gtk_widget_hide($scrolled_window);
		$app->set_usize(600,295);
	}
}

sub on_clear1_activate {
	$textbox->freeze;
	$textbox->delete_text;
	$WORD_INDEX = 0;
	@WORD_LIST = ();
	$textbox->thaw;
	return 1;
}

sub on_openurl_activate {
	gtk_widget_show($urldialog);
}

##
# Toolbar Callbacks
##
sub on_go_clicked {
	if ($GO_CLICKED == 1) {
		$GO_CLICKED = 0;
		$appbar->set_status("At word $WORD_INDEX of $#WORD_LIST.");	
	} else {
		$GO_CLICKED = 1;
		my $status = "Reading at " . 
			int( 60000 / $scale->get_adjustment->value) . 
			" words per min. Click GO again to stop.";
		$appbar->set_status($status);	
	}
	return 1;
}
sub on_prev_clicked {
	if ($WORD_INDEX > 1) {
		$WORD_INDEX--;
		display_word();
	}
	return 1;
}
sub on_next_clicked {
	if (defined $WORD_LIST[$WORD_INDEX]{'word'}) {
		$WORD_INDEX++;
		display_word();
	}
	return 1;
}

##
# Dialog Callbacks
##

# This function disappoints me because the file dialog takes
# too long to hide when loading large files. If anyone knows 
# how to fix this please send me some email
sub on_fileselection_ok_button_clicked {
	my $filename = $fileselection->get_filename;
	$TOTAL_LINES = build_word_index($filename);
	$WORD_INDEX = 0;
}

sub on_urlentry_activate {
	my $urlname = "http://";
	$urlname .= $urlentry->get_text;
	$TOTAL_LINES = build_word_index($urlname);
	$WORD_INDEX = 0;
}
	
sub on_fontselection_ok_button_clicked {
	$font = $fontselection->get_font_name(); 
}


sub on_color_dialog_activate {
        my @color = $colorpicker1->get_d();
	$FONT_COLOR->{ 'red' } = $color[0] * 65535.0;
	$FONT_COLOR->{ 'green' } = $color[1] * 65535.0;
	$FONT_COLOR->{ 'blue' } = $color[2] * 65535.0;
	$FONT_COLOR = $colormap->color_alloc( $FONT_COLOR );
}


sub on_goto_word_clicked {
	my $value = $word_number_entry->get_text;
	my $word = $wordentry->get_text;
	if ($value ne "") {
		# if (!$value =~ /^\d*$/) { return 1; }
		if (!exists $WORD_LIST[$value]{'word'}) {
			$appbar->set_status('Not a valid entry...');
		} else {	
			$WORD_INDEX = $value;
			$current_word_lable->set_text($WORD_INDEX);
			display_word();	
		}
	}
	if (defined $word) { 
		for (my $i=$WORD_INDEX+1; $i < $#WORD_LIST; $i++) {
			if ($WORD_LIST[$i]{'word'} =~ /$word/) {
				$WORD_INDEX = $i;
				$current_word_lable->set_text($WORD_INDEX);
				display_word();
				last;
			}
		}
	 }
	return 1;
}

##
# Events and Timers
##

# This is the timer function, it is executed once
# every interval as set by the 
# $scale->get_adjustment->value
sub display_update {
	if ($GO_CLICKED == 1) {
		if (defined $WORD_LIST[$WORD_INDEX+1]{'word'} ) {
			$WORD_INDEX++;
		}	
		display_word();
		update_timer();
	     }
	return 1;
}

# Capture the new value and recreate the timer function
sub scale_changed {
	my $value = $scale->get_adjustment->value;
	Gtk->timeout_remove( $timer );
	$timer = Gtk->timeout_add( $value, \&display_update, NULL );
}

sub on_plus_clicked {
        my $value = $scale->get_adjustment->value;
	if ($value == 10) { return 1 }
	my $newval = (((POSIX::ceil($value / 100)) * 100) - 50);
	if ($value == $newval) { $newval-=50 };
	if ($newval == 0) { $newval = 10 }
	my Gtk::Adjustment($adj) = $scale->get_adjustment;
	$adj->set_value($newval);
	$scale->set_adjustment( $adj );
	scale_changed();
	return 1;
}

sub on_minus_clicked {
        my $value = $scale->get_adjustment->value;
	my $newval = (((int($value / 100)) * 100) + 50);
	if ($value == $newval) { $newval+=50 };
	my Gtk::Adjustment($adj) = $scale->get_adjustment;
	$adj->set_value($newval);
	$scale->set_adjustment( $adj );
	scale_changed();
}

sub update_timer {
   my $word = $WORD_LIST[$WORD_INDEX]{'word'};
   my $value = $scale->get_adjustment->value;
   my $modify = 0;

   my $TIME_MULTI_PUNCT = ($value) * 2;
   my $TIME_NEW_PARAGRAPH = ($value) * 3/4;
   my $AVERAGE_WORD_LENGTH = 7;
   my $UPDATE_AFTER_WORDS = 10;

   $modify = ((length($word) - $AVERAGE_WORD_LENGTH) * ($value)) / $AVERAGE_WORD_LENGTH;
   $modify = 0 if $modify < 0;

   $modify += $TIME_NEW_PARAGRAPH if (defined($PARAGRAPH_INDEX{$WORD_INDEX}));

   if ($word =~ /(\.\.|\,|\!\!|\?\?)$/) {
      $value = $TIME_MULTI_PUNCT + $modify;
   } else {
      $value += $modify;
   }

   Gtk->timeout_remove( $timer );
   $timer = Gtk->timeout_add( $value, \&display_update, NULL );

   $c++;
   $time += $value;
   if ($c > $UPDATE_AFTER_WORDS) {
      my $status = "Reading at " . int($c/($time/60000)) . " words/min.";
      $appbar->set_status($status);	
      $c = 0;
      $time = 0;
   }

}

##
# Helper Functions
##

# This function creates the global $WORD_LIST structure.
# It parses the text character by character to identify 
# words. These structures are the stored in the array in 
# the following format:
#                                  /---> word
# $WORD_LIST [0 .. $#] ---> object-|---> character where word starts
#                                  \---> character where word ends
#				    ---> line number
sub build_word_index {
	my $filename = shift;
	my $wordcount = 0;
	my $wasspace = 0;
	my $start = 0;
	my $end = 0;
	my $line_number = 0;
	my $word = "";
	my $index = 0;
	my $oldindex = 0;
	my $x = 0;	
	my @array = ();
	
	$appbar->set_status("Building word index...");
	$textbox->freeze;
	$textbox->delete_text;
	@WORD_LIST = ();
	if (lc($filename) =~ /pdf$/) {
		open (FILE, "pdftotext \"$filename\" - |");
		@array = <FILE>;
	} elsif ($filename =~ "^http://" || lc($filename) =~ /html$/ 
		 || lc($filename) =~ /htm$/) {
		open (FILE, "lynx -dump -preparsed \"$filename\" |");
		@array = <FILE>;
	} else {
		open (FILE, $filename);
		@array = <FILE>;
	}

	my $prevLine = undef;
	my $paraFound = 0;
	foreach (@array) {
	   $paraFound = 0;

	   $line_number++;
	   $index = $textbox->insert_text($_, $index);	
	   for (my $i = $oldindex; $i < $index; $i++) {
	      my $char = $textbox->get_chars($i,$i + 1);
	      if ($char =~ /\s/) { 
		 if ($wasspace == 0) {
		    # Detect new paragraph, and record the previous word
		    if (! $paraFound && defined($prevLine) && $wordcount && (/^\s+/ || $prevLine =~ /^\s*$/)) {
		       $paraFound = 1;
		       $PARAGRAPH_INDEX{$wordcount} = 1;
		    }

		    $end = $i;
		    $wordcount++;
		    $WORD_LIST[$wordcount]{'word'} = $word;
		    $WORD_LIST[$wordcount]{'start'} = $start;
		    $WORD_LIST[$wordcount]{'end'} = $end;
		    $WORD_LIST[$wordcount]{'line'} = $line_number;
		    $word = "";
		 }
		 $wasspace = 1;
		 next;
	      } else {
		 if ($wasspace == 1) {
		    $start = $i;
		 }
		 $word .= $char;
		 $wasspace = 0;
	      }
	   }
	   $oldindex = $index;
	   
	   $prevLine = $_;
	}
	$textbox->thaw();
	$appbar->set_status("");	
	$LOCATION = $filename;
	return $line_number;
}

# This function updates the canvas	
sub display_word {
        if (!exists $WORD_LIST[$WORD_INDEX]{'word'}) {
		$appbar->set_status("Please load a file first...");
		$GO_CLICKED = 0;
		return 1;
	}
	# First we update the textbox and scroll
	$textbox->select_region($WORD_LIST[$WORD_INDEX]{'start'},
		$WORD_LIST[$WORD_INDEX]{'end'});
	# This is the text scrolling code. Look storing the line
	# number is useful after all!
	if ($TEXT_SCROLL == 1) {
		my $position = $WORD_LIST[$WORD_INDEX]{'line'} - 3;
		my $length = $TOTAL_LINES;
		my $percent = ($position / $length);
		my $maxval = $scrolled_window->get_vadjustment->upper;
		my $newval = $maxval * $percent;
		my Gtk::Adjustment($vadj) = $scrolled_window->get_vadjustment;
		$vadj->set_value($newval);
		$scrolled_window->set_vadjustment( $vadj );
	}
		
	# Then we write on the canvas	
        if (defined $txt) { $txt->destroy }
	$txt = $canvas_group->new($canvas_group, "Gnome::CanvasText",
		x => 50,
		y => 50,
		text => $WORD_LIST[$WORD_INDEX]{'word'},
		fill_color_gdk => $FONT_COLOR,
		# fill_color => 'steelblue',
		font_gdk => load Gtk::Gdk::Font($font),
		anchor => 'center',
	);
	return 1;	
}

# Session Saving Code
sub gnomersvp_save_session {
	open (CONFIG, "> $HOME/.gnomersvprc");
	print CONFIG "TEXT_SCROLL\t$TEXT_SCROLL\n";
	print CONFIG "FONT\t$font\n";
	print CONFIG "TEXTBOX\t";
	if ($textbox_toggle->active) {
		print CONFIG "1\n";
	} else {
		print CONFIG "0\n";
	}
	print CONFIG "SPEED\t" . $scale->get_adjustment->value . "\n";
	print CONFIG "FONT_COLOR\t" . $FONT_COLOR->{'red'} . ":"
				    . $FONT_COLOR->{'green'} . ":"
				    . $FONT_COLOR->{'blue'} . "\n";
	if ($location_toggle->active) {
		if (defined $LOCATION) {
			print CONFIG "LOCATION\t" . $LOCATION . ":" . $WORD_INDEX . "\n";
		}
		print CONFIG "LTOGGLE\t1";
	} else {
		print CONFIG "LTOGGLE\t0";
	}
	close (CONFIG);
}

__DATA__

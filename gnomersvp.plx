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
<?xml version="1.0"?>
<GTK-Interface>

<project>
  <name>GnomeRSVP</name>
  <program_name>gnomersvp</program_name>
  <directory></directory>
  <source_directory>src</source_directory>
  <pixmaps_directory>pixmaps</pixmaps_directory>
  <language>C</language>
  <gnome_support>True</gnome_support>
  <gettext_support>True</gettext_support>
</project>

<widget>
  <class>GnomeApp</class>
  <name>app1</name>
  <width>600</width>
  <height>450</height>
  <signal>
    <name>destroy</name>
    <handler>gtk_main_quit</handler>
    <last_modification_time>Thu, 22 Feb 2001 02:01:57 GMT</last_modification_time>
  </signal>
  <title>Gnome RSVP</title>
  <type>GTK_WINDOW_TOPLEVEL</type>
  <position>GTK_WIN_POS_NONE</position>
  <modal>False</modal>
  <allow_shrink>False</allow_shrink>
  <allow_grow>True</allow_grow>
  <auto_shrink>True</auto_shrink>
  <wmclass_name>grsvp</wmclass_name>
  <wmclass_class>grsvp</wmclass_class>
  <enable_layout_config>True</enable_layout_config>

  <widget>
    <class>GnomeDock</class>
    <child_name>GnomeApp:dock</child_name>
    <name>dock1</name>
    <allow_floating>True</allow_floating>
    <child>
      <padding>0</padding>
      <expand>True</expand>
      <fill>True</fill>
    </child>

    <widget>
      <class>GnomeDockItem</class>
      <name>dockitem1</name>
      <border_width>2</border_width>
      <placement>GNOME_DOCK_TOP</placement>
      <band>0</band>
      <position>0</position>
      <offset>0</offset>
      <locked>False</locked>
      <exclusive>True</exclusive>
      <never_floating>False</never_floating>
      <never_vertical>True</never_vertical>
      <never_horizontal>False</never_horizontal>
      <shadow_type>GTK_SHADOW_OUT</shadow_type>

      <widget>
	<class>GtkMenuBar</class>
	<name>menubar1</name>
	<shadow_type>GTK_SHADOW_NONE</shadow_type>

	<widget>
	  <class>GtkMenuItem</class>
	  <name>file1</name>
	  <stock_item>GNOMEUIINFO_MENU_FILE_TREE</stock_item>

	  <widget>
	    <class>GtkMenu</class>
	    <name>file1_menu</name>

	    <widget>
	      <class>GtkPixmapMenuItem</class>
	      <name>open1</name>
	      <signal>
		<name>activate</name>
		<handler>on_open1_activate</handler>
		<last_modification_time>Thu, 27 Jan 2000 21:46:34 GMT</last_modification_time>
	      </signal>
	      <stock_item>GNOMEUIINFO_MENU_OPEN_ITEM</stock_item>
	    </widget>

	    <widget>
	      <class>GtkPixmapMenuItem</class>
	      <name>open_url1</name>
	      <tooltip>Open URL</tooltip>
	      <accelerator>
		<modifiers>GDK_CONTROL_MASK</modifiers>
		<key>GDK_u</key>
		<signal>activate</signal>
	      </accelerator>
	      <signal>
		<name>activate</name>
		<handler>on_openurl_activate</handler>
		<last_modification_time>Sun, 25 Feb 2001 22:12:34 GMT</last_modification_time>
	      </signal>
	      <label>Open _URL...</label>
	      <right_justify>False</right_justify>
	      <stock_icon>GNOME_STOCK_MENU_OPEN</stock_icon>
	    </widget>

	    <widget>
	      <class>GtkMenuItem</class>
	      <name>separator1</name>
	      <right_justify>False</right_justify>
	    </widget>

	    <widget>
	      <class>GtkPixmapMenuItem</class>
	      <name>exit1</name>
	      <signal>
		<name>activate</name>
		<handler>gtk_main_quit</handler>
		<last_modification_time>Mon, 19 Feb 2001 18:01:45 GMT</last_modification_time>
	      </signal>
	      <stock_item>GNOMEUIINFO_MENU_EXIT_ITEM</stock_item>
	    </widget>
	  </widget>
	</widget>

	<widget>
	  <class>GtkMenuItem</class>
	  <name>edit1</name>
	  <stock_item>GNOMEUIINFO_MENU_EDIT_TREE</stock_item>

	  <widget>
	    <class>GtkMenu</class>
	    <name>edit1_menu</name>

	    <widget>
	      <class>GtkPixmapMenuItem</class>
	      <name>clear1</name>
	      <signal>
		<name>activate</name>
		<handler>on_clear1_activate</handler>
		<last_modification_time>Thu, 27 Jan 2000 21:46:34 GMT</last_modification_time>
	      </signal>
	      <stock_item>GNOMEUIINFO_MENU_CLEAR_ITEM</stock_item>
	    </widget>

	    <widget>
	      <class>GtkMenuItem</class>
	      <name>separator1</name>
	      <right_justify>False</right_justify>
	    </widget>

	    <widget>
	      <class>GtkPixmapMenuItem</class>
	      <name>goto_word</name>
	      <signal>
		<name>activate</name>
		<handler>on_goto_word_activate</handler>
		<last_modification_time>Thu, 22 Feb 2001 16:10:27 GMT</last_modification_time>
	      </signal>
	      <label>Goto Word...</label>
	      <right_justify>False</right_justify>
	      <stock_icon>GNOME_STOCK_MENU_SEARCH</stock_icon>
	    </widget>
	  </widget>
	</widget>

	<widget>
	  <class>GtkMenuItem</class>
	  <name>settings1</name>
	  <stock_item>GNOMEUIINFO_MENU_SETTINGS_TREE</stock_item>

	  <widget>
	    <class>GtkMenu</class>
	    <name>settings1_menu</name>

	    <widget>
	      <class>GtkCheckMenuItem</class>
	      <name>textboxcheck</name>
	      <signal>
		<name>activate</name>
		<handler>on_textbox_toggle_activate</handler>
		<last_modification_time>Mon, 23 Apr 2001 16:01:27 GMT</last_modification_time>
	      </signal>
	      <label>Show Text Box</label>
	      <active>True</active>
	      <always_show_toggle>True</always_show_toggle>
	    </widget>

	    <widget>
	      <class>GtkCheckMenuItem</class>
	      <name>scrollcheck</name>
	      <signal>
		<name>activate</name>
		<handler>on_scrollcheck_activate</handler>
		<last_modification_time>Thu, 22 Feb 2001 21:35:39 GMT</last_modification_time>
	      </signal>
	      <label>Scroll Text</label>
	      <active>True</active>
	      <always_show_toggle>True</always_show_toggle>
	    </widget>

	    <widget>
	      <class>GtkCheckMenuItem</class>
	      <name>location_toggle</name>
	      <signal>
		<name>activate</name>
		<handler>on_location_toggle_activate</handler>
		<last_modification_time>Mon, 28 May 2001 23:32:46 GMT</last_modification_time>
	      </signal>
	      <label>Remember Location</label>
	      <active>True</active>
	      <always_show_toggle>True</always_show_toggle>
	    </widget>

	    <widget>
	      <class>GtkPixmapMenuItem</class>
	      <name>preferences1</name>
	      <signal>
		<name>activate</name>
		<handler>on_preferences_activate</handler>
		<last_modification_time>Thu, 22 Feb 2001 21:33:11 GMT</last_modification_time>
	      </signal>
	      <label>Select Font...</label>
	      <right_justify>False</right_justify>
	      <stock_icon>GNOME_STOCK_MENU_FONT</stock_icon>
	    </widget>

	    <widget>
	      <class>GtkPixmapMenuItem</class>
	      <name>select_font_color</name>
	      <signal>
		<name>activate</name>
		<handler>on_select_font_color_activate</handler>
		<last_modification_time>Mon, 28 May 2001 23:01:02 GMT</last_modification_time>
	      </signal>
	      <label>Select Font Color...</label>
	      <right_justify>False</right_justify>
	      <stock_icon>GNOME_STOCK_MENU_CONVERT</stock_icon>
	    </widget>
	  </widget>
	</widget>

	<widget>
	  <class>GtkMenuItem</class>
	  <name>help1</name>
	  <stock_item>GNOMEUIINFO_MENU_HELP_TREE</stock_item>

	  <widget>
	    <class>GtkMenu</class>
	    <name>help1_menu</name>

	    <widget>
	      <class>GtkPixmapMenuItem</class>
	      <name>about1</name>
	      <signal>
		<name>activate</name>
		<handler>on_about1_activate</handler>
		<last_modification_time>Thu, 27 Jan 2000 21:46:34 GMT</last_modification_time>
	      </signal>
	      <stock_item>GNOMEUIINFO_MENU_ABOUT_ITEM</stock_item>
	    </widget>
	  </widget>
	</widget>
      </widget>
    </widget>

    <widget>
      <class>GnomeDockItem</class>
      <name>dockitem2</name>
      <border_width>1</border_width>
      <placement>GNOME_DOCK_TOP</placement>
      <band>1</band>
      <position>0</position>
      <offset>0</offset>
      <locked>False</locked>
      <exclusive>True</exclusive>
      <never_floating>False</never_floating>
      <never_vertical>False</never_vertical>
      <never_horizontal>False</never_horizontal>
      <shadow_type>GTK_SHADOW_OUT</shadow_type>

      <widget>
	<class>GtkToolbar</class>
	<name>toolbar1</name>
	<border_width>1</border_width>
	<orientation>GTK_ORIENTATION_HORIZONTAL</orientation>
	<type>GTK_TOOLBAR_BOTH</type>
	<space_size>16</space_size>
	<space_style>GTK_TOOLBAR_SPACE_LINE</space_style>
	<relief>GTK_RELIEF_NONE</relief>
	<tooltips>False</tooltips>

	<widget>
	  <class>GtkButton</class>
	  <child_name>Toolbar:button</child_name>
	  <name>button1</name>
	  <tooltip>Previous Word</tooltip>
	  <signal>
	    <name>clicked</name>
	    <handler>on_prev_clicked</handler>
	    <last_modification_time>Sun, 30 Jan 2000 14:11:41 GMT</last_modification_time>
	  </signal>
	  <label>Prev</label>
	  <stock_pixmap>GNOME_STOCK_PIXMAP_BACK</stock_pixmap>
	</widget>

	<widget>
	  <class>GtkButton</class>
	  <child_name>Toolbar:button</child_name>
	  <name>button2</name>
	  <tooltip>Next Word</tooltip>
	  <signal>
	    <name>clicked</name>
	    <handler>on_next_clicked</handler>
	    <last_modification_time>Sun, 30 Jan 2000 14:12:11 GMT</last_modification_time>
	  </signal>
	  <label>Next</label>
	  <stock_pixmap>GNOME_STOCK_PIXMAP_FORWARD</stock_pixmap>
	</widget>

	<widget>
	  <class>GtkButton</class>
	  <child_name>Toolbar:button</child_name>
	  <name>button3</name>
	  <tooltip>Start RSVP</tooltip>
	  <accelerator>
	    <modifiers>0</modifiers>
	    <key>GDK_space</key>
	    <signal>clicked</signal>
	  </accelerator>
	  <signal>
	    <name>clicked</name>
	    <handler>on_go_clicked</handler>
	    <last_modification_time>Sun, 30 Jan 2000 14:12:26 GMT</last_modification_time>
	  </signal>
	  <label>GO</label>
	  <stock_pixmap>GNOME_STOCK_PIXMAP_EXEC</stock_pixmap>
	</widget>
      </widget>
    </widget>

    <widget>
      <class>GtkVBox</class>
      <child_name>GnomeDock:contents</child_name>
      <name>vbox1</name>
      <homogeneous>False</homogeneous>
      <spacing>0</spacing>

      <widget>
	<class>GtkScrolledWindow</class>
	<name>scrolledwindow1</name>
	<height>200</height>
	<hscrollbar_policy>GTK_POLICY_NEVER</hscrollbar_policy>
	<vscrollbar_policy>GTK_POLICY_NEVER</vscrollbar_policy>
	<hupdate_policy>GTK_UPDATE_CONTINUOUS</hupdate_policy>
	<vupdate_policy>GTK_UPDATE_CONTINUOUS</vupdate_policy>
	<child>
	  <padding>0</padding>
	  <expand>False</expand>
	  <fill>False</fill>
	</child>

	<widget>
	  <class>GtkViewport</class>
	  <name>viewport1</name>
	  <shadow_type>GTK_SHADOW_IN</shadow_type>

	  <widget>
	    <class>GtkHBox</class>
	    <name>hbox1</name>
	    <width>500</width>
	    <height>200</height>
	    <homogeneous>False</homogeneous>
	    <spacing>0</spacing>

	    <widget>
	      <class>GtkVBox</class>
	      <name>vbox2</name>
	      <homogeneous>True</homogeneous>
	      <spacing>0</spacing>
	      <child>
		<padding>0</padding>
		<expand>True</expand>
		<fill>True</fill>
	      </child>

	      <widget>
		<class>GtkButton</class>
		<name>button4</name>
		<can_focus>True</can_focus>
		<signal>
		  <name>clicked</name>
		  <handler>on_plus_clicked</handler>
		  <last_modification_time>Thu, 22 Feb 2001 21:45:27 GMT</last_modification_time>
		</signal>
		<label>+</label>
		<relief>GTK_RELIEF_NORMAL</relief>
		<child>
		  <padding>0</padding>
		  <expand>True</expand>
		  <fill>True</fill>
		</child>
	      </widget>

	      <widget>
		<class>GtkButton</class>
		<name>button5</name>
		<can_focus>True</can_focus>
		<signal>
		  <name>clicked</name>
		  <handler>on_minus_clicked</handler>
		  <last_modification_time>Thu, 22 Feb 2001 21:45:42 GMT</last_modification_time>
		</signal>
		<label>-
</label>
		<relief>GTK_RELIEF_NORMAL</relief>
		<child>
		  <padding>0</padding>
		  <expand>True</expand>
		  <fill>True</fill>
		</child>
	      </widget>
	    </widget>

	    <widget>
	      <class>GtkScrolledWindow</class>
	      <name>scrolledwindow3</name>
	      <width>500</width>
	      <height>200</height>
	      <hscrollbar_policy>GTK_POLICY_NEVER</hscrollbar_policy>
	      <vscrollbar_policy>GTK_POLICY_NEVER</vscrollbar_policy>
	      <hupdate_policy>GTK_UPDATE_CONTINUOUS</hupdate_policy>
	      <vupdate_policy>GTK_UPDATE_CONTINUOUS</vupdate_policy>
	      <child>
		<padding>0</padding>
		<expand>True</expand>
		<fill>True</fill>
	      </child>

	      <widget>
		<class>GnomeCanvas</class>
		<name>canvas2</name>
		<width>500</width>
		<height>200</height>
		<can_focus>True</can_focus>
		<anti_aliased>False</anti_aliased>
		<scroll_x1>0</scroll_x1>
		<scroll_y1>0</scroll_y1>
		<scroll_x2>100</scroll_x2>
		<scroll_y2>100</scroll_y2>
		<pixels_per_unit>1</pixels_per_unit>
	      </widget>
	    </widget>

	    <widget>
	      <class>GtkVScale</class>
	      <name>speedscale</name>
	      <can_focus>True</can_focus>
	      <signal>
		<name>button_release_event</name>
		<handler>scale_changed</handler>
		<last_modification_time>Thu, 22 Feb 2001 01:04:28 GMT</last_modification_time>
	      </signal>
	      <draw_value>True</draw_value>
	      <value_pos>GTK_POS_BOTTOM</value_pos>
	      <digits>0</digits>
	      <policy>GTK_UPDATE_CONTINUOUS</policy>
	      <value>300</value>
	      <lower>10</lower>
	      <upper>500</upper>
	      <step>25</step>
	      <page>0</page>
	      <page_size>0</page_size>
	      <child>
		<padding>0</padding>
		<expand>True</expand>
		<fill>True</fill>
	      </child>
	    </widget>
	  </widget>
	</widget>
      </widget>

      <widget>
	<class>GtkScrolledWindow</class>
	<name>scrolledwindow2</name>
	<hscrollbar_policy>GTK_POLICY_NEVER</hscrollbar_policy>
	<vscrollbar_policy>GTK_POLICY_ALWAYS</vscrollbar_policy>
	<hupdate_policy>GTK_UPDATE_CONTINUOUS</hupdate_policy>
	<vupdate_policy>GTK_UPDATE_CONTINUOUS</vupdate_policy>
	<child>
	  <padding>0</padding>
	  <expand>True</expand>
	  <fill>True</fill>
	</child>

	<widget>
	  <class>GtkText</class>
	  <name>etext</name>
	  <can_focus>True</can_focus>
	  <editable>False</editable>
	  <text></text>
	</widget>
      </widget>
    </widget>
  </widget>

  <widget>
    <class>GnomeAppBar</class>
    <child_name>GnomeApp:appbar</child_name>
    <name>appbar1</name>
    <has_progress>True</has_progress>
    <has_status>True</has_status>
    <child>
      <padding>0</padding>
      <expand>True</expand>
      <fill>True</fill>
    </child>
  </widget>
</widget>

<widget>
  <class>GtkFileSelection</class>
  <name>fileselection</name>
  <border_width>10</border_width>
  <visible>False</visible>
  <signal>
    <name>delete_event</name>
    <handler>gtk_widget_hide</handler>
    <object>fileselection</object>
    <last_modification_time>Mon, 19 Feb 2001 18:07:06 GMT</last_modification_time>
  </signal>
  <title>Select File</title>
  <type>GTK_WINDOW_TOPLEVEL</type>
  <position>GTK_WIN_POS_NONE</position>
  <modal>False</modal>
  <allow_shrink>False</allow_shrink>
  <allow_grow>True</allow_grow>
  <auto_shrink>False</auto_shrink>
  <show_file_op_buttons>False</show_file_op_buttons>

  <widget>
    <class>GtkButton</class>
    <child_name>FileSel:ok_button</child_name>
    <name>ok_button1</name>
    <can_default>True</can_default>
    <can_focus>True</can_focus>
    <signal>
      <name>clicked</name>
      <handler>on_fileselection_ok_button_clicked</handler>
      <last_modification_time>Thu, 22 Feb 2001 02:33:24 GMT</last_modification_time>
    </signal>
    <signal>
      <name>clicked</name>
      <handler>gtk_widget_hide</handler>
      <object>fileselection</object>
      <last_modification_time>Thu, 22 Feb 2001 02:35:12 GMT</last_modification_time>
    </signal>
    <label>OK</label>
    <relief>GTK_RELIEF_NORMAL</relief>
  </widget>

  <widget>
    <class>GtkButton</class>
    <child_name>FileSel:cancel_button</child_name>
    <name>cancel_button1</name>
    <can_default>True</can_default>
    <can_focus>True</can_focus>
    <signal>
      <name>clicked</name>
      <handler>gtk_widget_hide</handler>
      <object>fileselection</object>
      <last_modification_time>Fri, 28 Jan 2000 13:02:13 GMT</last_modification_time>
    </signal>
    <label>Cancel</label>
    <relief>GTK_RELIEF_NORMAL</relief>
  </widget>
</widget>

<widget>
  <class>GnomeAbout</class>
  <name>about2</name>
  <visible>False</visible>
  <signal>
    <name>close</name>
    <handler>gtk_widget_hide</handler>
    <last_modification_time>Fri, 16 Feb 2001 04:26:47 GMT</last_modification_time>
  </signal>
  <modal>True</modal>
  <copyright>(C) 2001 FreeSoftware Foundation</copyright>
  <authors>Gregory S. Hayes
</authors>
  <comments>Gnome RSVP is designed to enhance text reading speed through the use of a technique known as rapid serial visual projection. See http://www.icebreaker.net/gnomersvp/ for more info.</comments>
</widget>

<widget>
  <class>GtkFontSelectionDialog</class>
  <name>fontselection</name>
  <border_width>4</border_width>
  <visible>False</visible>
  <signal>
    <name>destroy</name>
    <handler>gtk_widget_hide</handler>
    <object>fontselection</object>
    <last_modification_time>Thu, 22 Feb 2001 03:30:24 GMT</last_modification_time>
  </signal>
  <title>Select Font</title>
  <type>GTK_WINDOW_TOPLEVEL</type>
  <position>GTK_WIN_POS_NONE</position>
  <modal>False</modal>
  <allow_shrink>False</allow_shrink>
  <allow_grow>True</allow_grow>
  <auto_shrink>True</auto_shrink>

  <widget>
    <class>GtkButton</class>
    <child_name>FontSel:ok_button</child_name>
    <name>ok_button2</name>
    <can_default>True</can_default>
    <can_focus>True</can_focus>
    <signal>
      <name>clicked</name>
      <handler>gtk_widget_hide</handler>
      <object>fontselection</object>
      <last_modification_time>Thu, 22 Feb 2001 03:25:46 GMT</last_modification_time>
    </signal>
    <signal>
      <name>clicked</name>
      <handler>on_fontselection_ok_button_clicked</handler>
      <last_modification_time>Thu, 22 Feb 2001 03:26:18 GMT</last_modification_time>
    </signal>
    <label>OK</label>
    <relief>GTK_RELIEF_NORMAL</relief>
  </widget>

  <widget>
    <class>GtkButton</class>
    <child_name>FontSel:apply_button</child_name>
    <name>apply_button1</name>
    <can_default>True</can_default>
    <can_focus>True</can_focus>
    <signal>
      <name>clicked</name>
      <handler>on_fontselection_ok_button_clicked</handler>
      <last_modification_time>Thu, 22 Feb 2001 03:29:50 GMT</last_modification_time>
    </signal>
    <label>Apply</label>
    <relief>GTK_RELIEF_NORMAL</relief>
  </widget>

  <widget>
    <class>GtkButton</class>
    <child_name>FontSel:cancel_button</child_name>
    <name>cancel_button2</name>
    <can_default>True</can_default>
    <can_focus>True</can_focus>
    <signal>
      <name>clicked</name>
      <handler>gtk_widget_hide</handler>
      <object>fontselection</object>
      <last_modification_time>Thu, 22 Feb 2001 03:30:05 GMT</last_modification_time>
    </signal>
    <label>Cancel</label>
    <relief>GTK_RELIEF_NORMAL</relief>
  </widget>
</widget>

<widget>
  <class>GnomeDialog</class>
  <name>dialog1</name>
  <visible>False</visible>
  <signal>
    <name>destroy</name>
    <handler>gtk_widget_hide</handler>
    <object>dialog1</object>
    <last_modification_time>Thu, 22 Feb 2001 16:20:38 GMT</last_modification_time>
  </signal>
  <signal>
    <name>close</name>
    <handler>gtk_widget_hide</handler>
    <object>dialog1</object>
    <last_modification_time>Sun, 25 Feb 2001 22:50:47 GMT</last_modification_time>
  </signal>
  <title>Goto Word ...</title>
  <type>GTK_WINDOW_TOPLEVEL</type>
  <position>GTK_WIN_POS_NONE</position>
  <modal>False</modal>
  <allow_shrink>False</allow_shrink>
  <allow_grow>False</allow_grow>
  <auto_shrink>False</auto_shrink>
  <auto_close>False</auto_close>
  <hide_on_close>False</hide_on_close>

  <widget>
    <class>GtkVBox</class>
    <child_name>GnomeDialog:vbox</child_name>
    <name>dialog-vbox1</name>
    <homogeneous>False</homogeneous>
    <spacing>8</spacing>
    <child>
      <padding>4</padding>
      <expand>True</expand>
      <fill>True</fill>
    </child>

    <widget>
      <class>GtkHButtonBox</class>
      <child_name>GnomeDialog:action_area</child_name>
      <name>dialog-action_area1</name>
      <layout_style>GTK_BUTTONBOX_SPREAD</layout_style>
      <spacing>8</spacing>
      <child_min_width>85</child_min_width>
      <child_min_height>27</child_min_height>
      <child_ipad_x>7</child_ipad_x>
      <child_ipad_y>0</child_ipad_y>
      <child>
	<padding>0</padding>
	<expand>False</expand>
	<fill>True</fill>
	<pack>GTK_PACK_END</pack>
      </child>

      <widget>
	<class>GtkButton</class>
	<name>button6</name>
	<can_default>True</can_default>
	<can_focus>True</can_focus>
	<signal>
	  <name>clicked</name>
	  <handler>on_goto_word_clicked</handler>
	  <last_modification_time>Thu, 22 Feb 2001 16:21:20 GMT</last_modification_time>
	</signal>
	<signal>
	  <name>clicked</name>
	  <handler>gtk_widget_hide</handler>
	  <object>dialog1</object>
	  <last_modification_time>Thu, 22 Feb 2001 16:21:35 GMT</last_modification_time>
	</signal>
	<stock_button>GNOME_STOCK_BUTTON_OK</stock_button>
      </widget>

      <widget>
	<class>GtkButton</class>
	<name>button7</name>
	<can_default>True</can_default>
	<can_focus>True</can_focus>
	<signal>
	  <name>clicked</name>
	  <handler>on_goto_word_clicked</handler>
	  <last_modification_time>Thu, 22 Feb 2001 16:21:56 GMT</last_modification_time>
	</signal>
	<stock_button>GNOME_STOCK_BUTTON_APPLY</stock_button>
      </widget>

      <widget>
	<class>GtkButton</class>
	<name>button8</name>
	<can_default>True</can_default>
	<can_focus>True</can_focus>
	<signal>
	  <name>clicked</name>
	  <handler>gtk_widget_hide</handler>
	  <object>dialog1</object>
	  <last_modification_time>Thu, 22 Feb 2001 16:22:11 GMT</last_modification_time>
	</signal>
	<stock_button>GNOME_STOCK_BUTTON_CANCEL</stock_button>
      </widget>
    </widget>

    <widget>
      <class>GtkVBox</class>
      <name>vbox4</name>
      <homogeneous>False</homogeneous>
      <spacing>0</spacing>
      <child>
	<padding>0</padding>
	<expand>True</expand>
	<fill>True</fill>
      </child>

      <widget>
	<class>GtkHBox</class>
	<name>hbox2</name>
	<homogeneous>False</homogeneous>
	<spacing>0</spacing>
	<child>
	  <padding>0</padding>
	  <expand>True</expand>
	  <fill>True</fill>
	</child>

	<widget>
	  <class>GtkLabel</class>
	  <name>label1</name>
	  <label>Currently at word: </label>
	  <justify>GTK_JUSTIFY_CENTER</justify>
	  <wrap>False</wrap>
	  <xalign>0.5</xalign>
	  <yalign>0.5</yalign>
	  <xpad>10</xpad>
	  <ypad>0</ypad>
	  <child>
	    <padding>0</padding>
	    <expand>False</expand>
	    <fill>False</fill>
	  </child>
	</widget>

	<widget>
	  <class>GtkLabel</class>
	  <name>current_word_lable</name>
	  <label>0</label>
	  <justify>GTK_JUSTIFY_CENTER</justify>
	  <wrap>False</wrap>
	  <xalign>0.5</xalign>
	  <yalign>0.5</yalign>
	  <xpad>10</xpad>
	  <ypad>0</ypad>
	  <child>
	    <padding>0</padding>
	    <expand>False</expand>
	    <fill>False</fill>
	  </child>
	</widget>

	<widget>
	  <class>GtkLabel</class>
	  <name>label3</name>
	  <label>of</label>
	  <justify>GTK_JUSTIFY_RIGHT</justify>
	  <wrap>False</wrap>
	  <xalign>0.5</xalign>
	  <yalign>0.5</yalign>
	  <xpad>10</xpad>
	  <ypad>0</ypad>
	  <child>
	    <padding>0</padding>
	    <expand>False</expand>
	    <fill>False</fill>
	  </child>
	</widget>

	<widget>
	  <class>GtkLabel</class>
	  <name>total_word_lable</name>
	  <label>0</label>
	  <justify>GTK_JUSTIFY_CENTER</justify>
	  <wrap>False</wrap>
	  <xalign>0.5</xalign>
	  <yalign>0.5</yalign>
	  <xpad>0</xpad>
	  <ypad>0</ypad>
	  <child>
	    <padding>0</padding>
	    <expand>False</expand>
	    <fill>False</fill>
	  </child>
	</widget>
      </widget>

      <widget>
	<class>GtkHBox</class>
	<name>hbox5</name>
	<homogeneous>False</homogeneous>
	<spacing>0</spacing>
	<child>
	  <padding>0</padding>
	  <expand>True</expand>
	  <fill>True</fill>
	</child>

	<widget>
	  <class>GtkLabel</class>
	  <name>label8</name>
	  <label>Goto Word</label>
	  <justify>GTK_JUSTIFY_CENTER</justify>
	  <wrap>False</wrap>
	  <xalign>0.5</xalign>
	  <yalign>0.5</yalign>
	  <xpad>5</xpad>
	  <ypad>5</ypad>
	  <child>
	    <padding>0</padding>
	    <expand>False</expand>
	    <fill>False</fill>
	  </child>
	</widget>

	<widget>
	  <class>GtkEntry</class>
	  <name>wordentry</name>
	  <can_focus>True</can_focus>
	  <signal>
	    <name>activate</name>
	    <handler>on_goto_word_clicked</handler>
	    <last_modification_time>Wed, 28 Feb 2001 01:32:08 GMT</last_modification_time>
	  </signal>
	  <editable>True</editable>
	  <text_visible>True</text_visible>
	  <text_max_length>0</text_max_length>
	  <text></text>
	  <child>
	    <padding>0</padding>
	    <expand>True</expand>
	    <fill>True</fill>
	  </child>
	</widget>
      </widget>

      <widget>
	<class>GtkHBox</class>
	<name>hbox3</name>
	<homogeneous>False</homogeneous>
	<spacing>0</spacing>
	<child>
	  <padding>0</padding>
	  <expand>True</expand>
	  <fill>True</fill>
	</child>

	<widget>
	  <class>GtkLabel</class>
	  <name>label5</name>
	  <label>Start at Word #</label>
	  <justify>GTK_JUSTIFY_CENTER</justify>
	  <wrap>False</wrap>
	  <xalign>0.5</xalign>
	  <yalign>0.5</yalign>
	  <xpad>10</xpad>
	  <ypad>0</ypad>
	  <child>
	    <padding>0</padding>
	    <expand>False</expand>
	    <fill>False</fill>
	  </child>
	</widget>

	<widget>
	  <class>GtkEntry</class>
	  <name>word_number_entry</name>
	  <can_focus>True</can_focus>
	  <signal>
	    <name>activate</name>
	    <handler>on_goto_word_clicked</handler>
	    <last_modification_time>Thu, 22 Feb 2001 16:27:36 GMT</last_modification_time>
	  </signal>
	  <editable>True</editable>
	  <text_visible>True</text_visible>
	  <text_max_length>7</text_max_length>
	  <text></text>
	  <child>
	    <padding>0</padding>
	    <expand>True</expand>
	    <fill>True</fill>
	  </child>
	</widget>
      </widget>
    </widget>
  </widget>
</widget>

<widget>
  <class>GnomeDialog</class>
  <name>urldialog</name>
  <visible>False</visible>
  <signal>
    <name>destroy</name>
    <handler>gtk_widget_hide</handler>
    <object>urldialog</object>
    <last_modification_time>Sun, 25 Feb 2001 22:48:39 GMT</last_modification_time>
  </signal>
  <signal>
    <name>close</name>
    <handler>gtk_widget_hide</handler>
    <object>urldialog</object>
    <last_modification_time>Sun, 25 Feb 2001 22:49:39 GMT</last_modification_time>
  </signal>
  <type>GTK_WINDOW_TOPLEVEL</type>
  <position>GTK_WIN_POS_NONE</position>
  <modal>False</modal>
  <allow_shrink>False</allow_shrink>
  <allow_grow>False</allow_grow>
  <auto_shrink>False</auto_shrink>
  <auto_close>False</auto_close>
  <hide_on_close>False</hide_on_close>

  <widget>
    <class>GtkVBox</class>
    <child_name>GnomeDialog:vbox</child_name>
    <name>dialog-vbox2</name>
    <homogeneous>False</homogeneous>
    <spacing>8</spacing>
    <child>
      <padding>4</padding>
      <expand>True</expand>
      <fill>True</fill>
    </child>

    <widget>
      <class>GtkHButtonBox</class>
      <child_name>GnomeDialog:action_area</child_name>
      <name>dialog-action_area2</name>
      <layout_style>GTK_BUTTONBOX_SPREAD</layout_style>
      <spacing>8</spacing>
      <child_min_width>85</child_min_width>
      <child_min_height>27</child_min_height>
      <child_ipad_x>7</child_ipad_x>
      <child_ipad_y>0</child_ipad_y>
      <child>
	<padding>0</padding>
	<expand>False</expand>
	<fill>True</fill>
	<pack>GTK_PACK_END</pack>
      </child>

      <widget>
	<class>GtkButton</class>
	<name>button9</name>
	<can_default>True</can_default>
	<can_focus>True</can_focus>
	<signal>
	  <name>clicked</name>
	  <handler>on_urlentry_activate</handler>
	  <last_modification_time>Sun, 25 Feb 2001 22:09:02 GMT</last_modification_time>
	</signal>
	<signal>
	  <name>clicked</name>
	  <handler>gtk_widget_hide</handler>
	  <object>urldialog</object>
	  <last_modification_time>Sun, 25 Feb 2001 22:09:47 GMT</last_modification_time>
	</signal>
	<stock_button>GNOME_STOCK_BUTTON_OK</stock_button>
      </widget>

      <widget>
	<class>GtkButton</class>
	<name>button10</name>
	<can_default>True</can_default>
	<can_focus>True</can_focus>
	<signal>
	  <name>clicked</name>
	  <handler>on_urlentry_activate</handler>
	  <last_modification_time>Sun, 25 Feb 2001 22:10:42 GMT</last_modification_time>
	</signal>
	<stock_button>GNOME_STOCK_BUTTON_APPLY</stock_button>
      </widget>

      <widget>
	<class>GtkButton</class>
	<name>button11</name>
	<can_default>True</can_default>
	<can_focus>True</can_focus>
	<signal>
	  <name>clicked</name>
	  <handler>gtk_widget_hide</handler>
	  <object>urldialog</object>
	  <last_modification_time>Sun, 25 Feb 2001 22:10:58 GMT</last_modification_time>
	</signal>
	<stock_button>GNOME_STOCK_BUTTON_CANCEL</stock_button>
      </widget>
    </widget>

    <widget>
      <class>GtkVBox</class>
      <name>vbox5</name>
      <homogeneous>False</homogeneous>
      <spacing>0</spacing>
      <child>
	<padding>0</padding>
	<expand>True</expand>
	<fill>True</fill>
      </child>

      <widget>
	<class>GtkLabel</class>
	<name>label6</name>
	<label>Enter URL below:</label>
	<justify>GTK_JUSTIFY_CENTER</justify>
	<wrap>False</wrap>
	<xalign>0.5</xalign>
	<yalign>0.5</yalign>
	<xpad>5</xpad>
	<ypad>5</ypad>
	<child>
	  <padding>0</padding>
	  <expand>False</expand>
	  <fill>False</fill>
	</child>
      </widget>

      <widget>
	<class>GtkHBox</class>
	<name>hbox4</name>
	<homogeneous>False</homogeneous>
	<spacing>0</spacing>
	<child>
	  <padding>0</padding>
	  <expand>True</expand>
	  <fill>True</fill>
	</child>

	<widget>
	  <class>GtkLabel</class>
	  <name>label7</name>
	  <label>http://</label>
	  <justify>GTK_JUSTIFY_CENTER</justify>
	  <wrap>False</wrap>
	  <xalign>0.5</xalign>
	  <yalign>0.5</yalign>
	  <xpad>5</xpad>
	  <ypad>0</ypad>
	  <child>
	    <padding>0</padding>
	    <expand>False</expand>
	    <fill>False</fill>
	  </child>
	</widget>

	<widget>
	  <class>GtkEntry</class>
	  <name>urlentry</name>
	  <can_focus>True</can_focus>
	  <signal>
	    <name>activate</name>
	    <handler>on_urlentry_activate</handler>
	    <last_modification_time>Sun, 25 Feb 2001 22:08:35 GMT</last_modification_time>
	  </signal>
	  <editable>True</editable>
	  <text_visible>True</text_visible>
	  <text_max_length>0</text_max_length>
	  <text></text>
	  <child>
	    <padding>0</padding>
	    <expand>True</expand>
	    <fill>True</fill>
	  </child>
	</widget>
      </widget>
    </widget>
  </widget>
</widget>

<widget>
  <class>GnomeDialog</class>
  <name>color_dialog</name>
  <visible>False</visible>
  <signal>
    <name>destroy</name>
    <handler>gtk_widget_hide</handler>
    <object>color_dialog</object>
    <last_modification_time>Mon, 28 May 2001 20:49:01 GMT</last_modification_time>
  </signal>
  <signal>
    <name>close</name>
    <handler>gtk_widget_hide</handler>
    <object>color_dialog</object>
    <last_modification_time>Mon, 28 May 2001 20:49:25 GMT</last_modification_time>
  </signal>
  <title>Configure Text Color</title>
  <type>GTK_WINDOW_TOPLEVEL</type>
  <position>GTK_WIN_POS_NONE</position>
  <modal>False</modal>
  <allow_shrink>False</allow_shrink>
  <allow_grow>False</allow_grow>
  <auto_shrink>False</auto_shrink>
  <auto_close>False</auto_close>
  <hide_on_close>False</hide_on_close>

  <widget>
    <class>GtkVBox</class>
    <child_name>GnomeDialog:vbox</child_name>
    <name>dialog-vbox3</name>
    <homogeneous>False</homogeneous>
    <spacing>8</spacing>
    <child>
      <padding>4</padding>
      <expand>True</expand>
      <fill>True</fill>
    </child>

    <widget>
      <class>GtkHButtonBox</class>
      <child_name>GnomeDialog:action_area</child_name>
      <name>dialog-action_area3</name>
      <layout_style>GTK_BUTTONBOX_SPREAD</layout_style>
      <spacing>8</spacing>
      <child_min_width>85</child_min_width>
      <child_min_height>27</child_min_height>
      <child_ipad_x>7</child_ipad_x>
      <child_ipad_y>0</child_ipad_y>
      <child>
	<padding>0</padding>
	<expand>False</expand>
	<fill>True</fill>
	<pack>GTK_PACK_END</pack>
      </child>

      <widget>
	<class>GtkButton</class>
	<name>color_ok</name>
	<can_default>True</can_default>
	<can_focus>True</can_focus>
	<signal>
	  <name>clicked</name>
	  <handler>on_color_dialog_activate</handler>
	  <last_modification_time>Mon, 28 May 2001 20:48:09 GMT</last_modification_time>
	</signal>
	<signal>
	  <name>clicked</name>
	  <handler>gtk_widget_hide</handler>
	  <object>color_dialog</object>
	  <last_modification_time>Mon, 28 May 2001 20:48:25 GMT</last_modification_time>
	</signal>
	<stock_button>GNOME_STOCK_BUTTON_OK</stock_button>
      </widget>

      <widget>
	<class>GtkButton</class>
	<name>color_apply</name>
	<can_default>True</can_default>
	<can_focus>True</can_focus>
	<signal>
	  <name>clicked</name>
	  <handler>on_color_dialog_activate</handler>
	  <last_modification_time>Mon, 28 May 2001 20:48:38 GMT</last_modification_time>
	</signal>
	<stock_button>GNOME_STOCK_BUTTON_APPLY</stock_button>
      </widget>

      <widget>
	<class>GtkButton</class>
	<name>color_cancel</name>
	<can_default>True</can_default>
	<can_focus>True</can_focus>
	<signal>
	  <name>clicked</name>
	  <handler>gtk_widget_hide</handler>
	  <object>color_dialog</object>
	  <last_modification_time>Mon, 28 May 2001 20:47:17 GMT</last_modification_time>
	</signal>
	<stock_button>GNOME_STOCK_BUTTON_CANCEL</stock_button>
      </widget>
    </widget>

    <widget>
      <class>GtkTable</class>
      <name>table1</name>
      <rows>1</rows>
      <columns>2</columns>
      <homogeneous>True</homogeneous>
      <row_spacing>0</row_spacing>
      <column_spacing>0</column_spacing>
      <child>
	<padding>0</padding>
	<expand>False</expand>
	<fill>False</fill>
      </child>

      <widget>
	<class>GtkLabel</class>
	<name>label9</name>
	<label>Text Color</label>
	<justify>GTK_JUSTIFY_CENTER</justify>
	<wrap>False</wrap>
	<xalign>0</xalign>
	<yalign>0.5</yalign>
	<xpad>10</xpad>
	<ypad>10</ypad>
	<child>
	  <left_attach>0</left_attach>
	  <right_attach>1</right_attach>
	  <top_attach>0</top_attach>
	  <bottom_attach>1</bottom_attach>
	  <xpad>0</xpad>
	  <ypad>0</ypad>
	  <xexpand>False</xexpand>
	  <yexpand>False</yexpand>
	  <xshrink>False</xshrink>
	  <yshrink>False</yshrink>
	  <xfill>True</xfill>
	  <yfill>False</yfill>
	</child>
      </widget>

      <widget>
	<class>GnomeColorPicker</class>
	<name>colorpicker1</name>
	<can_focus>True</can_focus>
	<dither>True</dither>
	<use_alpha>False</use_alpha>
	<title>Pick a color</title>
	<child>
	  <left_attach>1</left_attach>
	  <right_attach>2</right_attach>
	  <top_attach>0</top_attach>
	  <bottom_attach>1</bottom_attach>
	  <xpad>0</xpad>
	  <ypad>0</ypad>
	  <xexpand>True</xexpand>
	  <yexpand>False</yexpand>
	  <xshrink>False</xshrink>
	  <yshrink>False</yshrink>
	  <xfill>True</xfill>
	  <yfill>False</yfill>
	</child>
      </widget>
    </widget>
  </widget>
</widget>

</GTK-Interface>

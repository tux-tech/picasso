#!/usr/bin/env perl
#
# PICASSO Engine v2.0 - WebP Image Conversion Engine
# Handles recursive directory conversion with all advanced options
#
# Full options support:
#   - Multiple output modes (subfolder, same_directory, custom_path, flatten)
#   - File handling modes (preserve, delete, move, backup)
#   - Resizing options
#   - Metadata control
#   - Lossless mode
#   - WebP optimization
#

use strict;
use warnings;
use File::Find;
use File::Path qw(make_path);
use File::Basename;
use File::Copy;
use File::Spec;
use Cwd qw(abs_path getcwd);
use POSIX qw(:sys_wait_h);

# Try to load optional modules
my $has_progress_bar = eval { require Term::ProgressBar; 1 };
my $has_json = eval { require JSON; JSON->import(); 1 };

# Command line arguments - expanded for all options
my ($src_dir, $quality, $method, $alpha_quality,
    $delete_originals, $output_subfolder, $backup_enabled,
    $backup_folder, $parallel_count, $verbose,
    $file_mode, $move_folder, $output_mode, $custom_path,
    $flatten, $preserve_structure, $append_suffix,
    $resize_enabled, $resize_width, $resize_height, $resize_max,
    $lossless, $preserve_exif, $preserve_icc, $strip_all) = @ARGV;

# Set defaults
$src_dir           //= '.';
$quality           //= 75;
$method            //= 4;
$alpha_quality     //= 90;
$delete_originals  //= 'false';
$output_subfolder  //= 'webp';
$backup_enabled    //= 'false';
$backup_folder     //= 'originals_backup';
$parallel_count    //= 1;
$verbose           //= 'false';
$file_mode         //= 'preserve';
$move_folder       //= '';
$output_mode       //= 'subfolder';
$custom_path       //= '';
$flatten           //= 'false';
$preserve_structure //= 'true';
$append_suffix     //= '';
$resize_enabled    //= 'false';
$resize_width      //= '';
$resize_height     //= '';
$resize_max        //= '';
$lossless          //= 'false';
$preserve_exif     //= 'true';
$preserve_icc      //= 'true';
$strip_all         //= 'false';

# Normalize boolean values
$delete_originals   = ($delete_originals eq 'true') ? 1 : 0;
$backup_enabled     = ($backup_enabled eq 'true') ? 1 : 0;
$verbose            = ($verbose eq 'true') ? 1 : 0;
$flatten            = ($flatten eq 'true') ? 1 : 0;
$preserve_structure = ($preserve_structure eq 'true') ? 1 : 0;
$resize_enabled     = ($resize_enabled eq 'true') ? 1 : 0;
$lossless           = ($lossless eq 'true') ? 1 : 0;
$preserve_exif      = ($preserve_exif eq 'true') ? 1 : 0;
$preserve_icc       = ($preserve_icc eq 'true') ? 1 : 0;
$strip_all          = ($strip_all eq 'true') ? 1 : 0;

# Statistics tracking
my %stats = (
    total_files     => 0,
    converted       => 0,
    failed          => 0,
    skipped         => 0,
    resized         => 0,
    original_size   => 0,
    converted_size  => 0,
    start_time      => time(),
    file_modes      => {
        preserved   => 0,
        deleted     => 0,
        moved       => 0,
        backed_up   => 0,
    },
);

# Parallel processing tracking
my @child_pids = ();
my $running_children = 0;
my $max_children = $parallel_count || 1;

# Output colors
my %COLORS = (
    RED     => "\033[0;31m",
    GREEN   => "\033[0;32m",
    YELLOW  => "\033[1;33m",
    BLUE    => "\033[0;34m",
    CYAN    => "\033[0;36m",
    MAGENTA => "\033[0;35m",
    WHITE   => "\033[1;37m",
    RESET   => "\033[0m",
    BOLD    => "\033[1m",
    DIM     => "\033[2m",
);

#--- Helper Functions ---

sub colorize {
    my ($color, $text) = @_;
    return $COLORS{$color} . $text . $COLORS{RESET};
}

sub print_status { print colorize('BLUE', '[*]') . " $@[0]\n"; }
sub print_success { print colorize('GREEN', '[✓]') . " $@[0]\n"; }
sub print_warning { print colorize('YELLOW', '[!]') . " $@[0]\n"; }
sub print_error { print colorize('RED', '[✗]') . " $@[0]\n"; }
sub print_info { print colorize('CYAN', '[i]') . " $@[0]\n"; }
sub print_verbose { print colorize('DIM', '[V]') . " $@[0]\n" if $verbose; }

sub format_size {
    my ($bytes) = @_;
    return "0 B" unless defined $bytes && $bytes > 0;

    my @units = ('B', 'KB', 'MB', 'GB', 'TB');
    my $unit_index = 0;

    while ($bytes >= 1024 && $unit_index < $#units) {
        $bytes /= 1024;
        $unit_index++;
    }

    return sprintf("%.2f %s", $bytes, $units[$unit_index]);
}

sub format_time {
    my ($seconds) = @_;
    return "0s" unless $seconds > 0;

    my $hours = int($seconds / 3600);
    my $minutes = int(($seconds % 3600) / 60);
    my $secs = $seconds % 60;

    if ($hours > 0) {
        return sprintf("%dh %dm %ds", $hours, $minutes, $secs);
    } elsif ($minutes > 0) {
        return sprintf("%dm %ds", $minutes, $secs);
    } else {
        return sprintf("%ds", $secs);
    }
}

#--- File Processing Functions ---

sub is_image {
    my ($file) = @_;
    return $file =~ /\.(jpe?g|png|gif|bmp|tiff?|webp)$/i;
}

sub is_webp {
    my ($file) = @_;
    return $file =~ /\.webp$/i;
}

sub get_output_path {
    my ($src_file, $src_dir, $out_dir, $suffix) = @_;
    
    $suffix //= '';
    
    # Get relative path from source directory
    my $rel_path = File::Spec->abs2rel($src_file, $src_dir);
    
    # Get directory and filename parts
    my ($filename, $directories, $extension) = fileparse($rel_path, qr/\.[^.]*/);
    
    # Build output path based on mode
    my $output_path;
    
    if ($flatten) {
        # Flatten mode: all files go to single directory
        # Add counter or handle duplicate names
        my $counter = 1;
        my $try_filename = $filename;
        $output_path = File::Spec->catfile($out_dir, "$try_filename$suffix.webp");
        
        while (-f $output_path) {
            $counter++;
            $output_path = File::Spec->catfile($out_dir, "${try_filename}_${counter}$suffix.webp");
        }
    } elsif ($preserve_structure) {
        # Preserve directory structure
        my $output_subdir = File::Spec->catdir($out_dir, $directories);
        $output_path = File::Spec->catfile($output_subdir, "$filename$suffix.webp");
    } else {
        $output_path = File::Spec->catfile($out_dir, "$filename$suffix.webp");
    }
    
    return $output_path;
}

sub get_target_directory {
    my ($src_dir) = @_;
    
    if ($output_mode eq 'custom_path' && $custom_path) {
        # Custom output path
        if (File::Spec->file_name_is_absolute($custom_path)) {
            return $custom_path;
        } else {
            return File::Spec->catdir($src_dir, $custom_path);
        }
    } elsif ($output_mode eq 'same_directory') {
        # Same as source
        return $src_dir;
    } elsif ($output_mode eq 'flatten') {
        # Flatten to single folder
        return File::Spec->catdir($src_dir, $output_subfolder // 'converted');
    } else {
        # Default: subfolder mode
        return File::Spec->catdir($src_dir, $output_subfolder // 'webp');
    }
}

sub create_backup {
    my ($src_file, $backup_dir, $src_dir) = @_;
    
    return unless $backup_enabled || $file_mode eq 'backup';
    
    my $target_dir = $backup_dir // File::Spec->catdir($src_dir, $backup_folder // 'originals_backup');
    
    # Get relative path
    my $rel_path = File::Spec->abs2rel($src_file, $src_dir);
    
    # Create backup path
    my $backup_path = File::Spec->catfile($target_dir, $rel_path);
    
    # Create backup directory
    my $backup_subdir = dirname($backup_path);
    make_path($backup_subdir) unless -d $backup_subdir;
    
    # Copy file to backup
    if (copy($src_file, $backup_path)) {
        print_verbose("Backed up: $src_file -> $backup_path");
        $stats{file_modes}{backed_up}++;
        return 1;
    } else {
        print_warning("Failed to backup: $src_file");
        return 0;
    }
}

sub move_original {
    my ($src_file, $move_dir, $src_dir) = @_;
    
    return unless $file_mode eq 'move' && $move_folder;
    
    my $target_dir = File::Spec->catdir($src_dir, $move_folder);
    
    # Get relative path
    my $rel_path = File::Spec->abs2rel($src_file, $src_dir);
    
    # Create move path
    my $move_path = File::Spec->catfile($target_dir, $rel_path);
    
    # Create directory
    my $move_subdir = dirname($move_path);
    make_path($move_subdir) unless -d $move_subdir;
    
    # Move file
    if (move($src_file, $move_path)) {
        print_verbose("Moved original: $src_file -> $move_path");
        $stats{file_modes}{moved}++;
        return 1;
    } else {
        print_warning("Failed to move: $src_file");
        return 0;
    }
}

sub build_cwebp_command {
    my ($src_file, $output_file, $q, $m, $a_q) = @_;
    
    my @cmd = ('cwebp');
    
    # Lossless mode
    if ($lossless) {
        push @cmd, '-lossless';
    } else {
        push @cmd, '-q', $q;
    }
    
    # Compression method
    push @cmd, '-m', $m;
    
    # Alpha quality
    push @cmd, '-alpha_q', $a_q;
    
    # Metadata handling
    if ($strip_all) {
        push @cmd, '-metadata', 'none';
    } else {
        my @meta;
        push @meta, 'exif' if $preserve_exif;
        push @meta, 'icc' if $preserve_icc;
        if (@meta) {
            push @cmd, '-metadata', join(',', @meta);
        }
    }
    
    # Resizing
    if ($resize_enabled) {
        if ($resize_width && $resize_height) {
            push @cmd, '-resize', $resize_width, $resize_height;
        } elsif ($resize_max) {
            # Max dimension resizing
            push @cmd, '-resize', $resize_max, $resize_max;
        }
    }
    
    # Quiet mode unless verbose
    push @cmd, '-quiet' unless $verbose;
    
    # Input and output
    push @cmd, $src_file, '-o', $output_file;
    
    return @cmd;
}

sub convert_image {
    my ($src_file, $output_file, $q, $m, $a_q) = @_;
    
    # Build command
    my @cmd = build_cwebp_command($src_file, $output_file, $q, $m, $a_q);
    
    print_verbose("Command: " . join(' ', @cmd));
    
    # Run conversion
    my $result = system(@cmd);
    
    if ($result == 0 && -f $output_file) {
        return 1;
    } else {
        print_error("Conversion failed: $src_file");
        return 0;
    }
}

sub optimize_webp {
    my ($src_file, $output_file, $q, $m) = @_;
    
    # Use webp encoder to re-compress
    # For optimization, we decode and re-encode
    
    my $temp_file = "$output_file.tmp";
    
    # Use cwebp with the WebP as input (it can decode WebP too)
    my @cmd = ('cwebp', '-q', $q, '-m', $m);
    
    if ($strip_all) {
        push @cmd, '-metadata', 'none';
    }
    
    push @cmd, '-quiet', $src_file, '-o', $temp_file;
    
    print_verbose("Optimizing: " . join(' ', @cmd));
    
    my $result = system(@cmd);
    
    if ($result == 0 && -f $temp_file) {
        # Check if new file is smaller
        my $orig_size = -s $src_file;
        my $new_size = -s $temp_file;
        
        if ($new_size < $orig_size) {
            move($temp_file, $output_file);
            return 1;
        } else {
            # Original is already optimal or better
            unlink $temp_file;
            print_verbose("Skipping: Original is already optimal");
            return -1;  # Special return for "skipped"
        }
    } else {
        unlink $temp_file if -f $temp_file;
        return 0;
    }
}

sub process_file {
    my ($src_file, $output_dir, $backup_dir, $src_root) = @_;
    
    # Skip if not an image
    unless (is_image($src_file)) {
        return;
    }
    
    $stats{total_files}++;
    
    # Get original size
    $stats{original_size} += -s $src_file // 0;
    
    # Determine if this is WebP optimization
    my $is_optimization = is_webp($src_file);
    
    # Get output path
    my $suffix = $append_suffix // '';
    my $output_file = get_output_path($src_file, $src_root, $output_dir, $suffix);
    
    # For same_directory mode with WebP source, need different approach
    if ($output_mode eq 'same_directory' && $is_optimization) {
        if (!$suffix) {
            # Need to use a temp approach
            $suffix = '_optimized';
            $output_file = get_output_path($src_file, $src_root, $output_dir, $suffix);
        }
    }
    
    # Create output directory
    my $output_subdir = dirname($output_file);
    make_path($output_subdir) unless -d $output_subdir;
    
    # Skip if output exists and is newer (unless optimization)
    if (!$is_optimization && -f $output_file && (stat($output_file))[9] >= (stat($src_file))[9]) {
        print_verbose("Skipping (up-to-date): $src_file");
        $stats{skipped}++;
        return;
    }
    
    # Handle file mode: backup
    if ($file_mode eq 'backup' || $backup_enabled) {
        create_backup($src_file, $backup_dir, $src_root);
    }
    
    # Verbose output
    if ($verbose) {
        my $rel = File::Spec->abs2rel($src_file, $src_root);
        print colorize('CYAN', '  → ') . "$rel\n";
    }
    
    # Convert or optimize
    my $success;
    if ($is_optimization) {
        $success = optimize_webp($src_file, $output_file, $quality, $method);
    } else {
        $success = convert_image($src_file, $output_file, $quality, $method, $alpha_quality);
    }
    
    if ($success > 0) {
        $stats{converted}++;
        $stats{converted_size} += -s $output_file // 0;
        
        # Handle file mode: delete
        if ($file_mode eq 'delete' || $delete_originals) {
            if (unlink($src_file)) {
                print_verbose("Deleted original: $src_file");
                $stats{file_modes}{deleted}++;
            }
        }
        # Handle file mode: move
        elsif ($file_mode eq 'move') {
            move_original($src_file, $move_folder, $src_root);
        }
        else {
            $stats{file_modes}{preserved}++;
        }
    } elsif ($success == 0) {
        $stats{failed}++;
    } else {
        # Skipped (optimization showed no benefit)
        $stats{skipped}++;
    }
}

#--- Parallel Processing ---

sub wait_for_child {
    my $pid = wait();
    if ($pid > 0) {
        @child_pids = grep { $_ != $pid } @child_pids;
        $running_children--;
    }
}

sub wait_for_all_children {
    while (@child_pids) {
        wait_for_child();
    }
}

sub reap_zombies {
    while ((my $pid = waitpid(-1, WNOHANG)) > 0) {
        @child_pids = grep { $_ != $pid } @child_pids;
        $running_children-- if $running_children > 0;
    }
}

#--- Main Processing ---

sub main {
    # Resolve absolute paths
    $src_dir = abs_path($src_dir);
    my $output_dir = get_target_directory($src_dir);
    my $backup_dir = File::Spec->catdir($src_dir, $backup_folder // 'originals_backup');
    
    # Validate source directory
    unless (-d $src_dir) {
        die "Source directory does not exist: $src_dir\n";
    }
    
    # Print header
    print "\n";
    print colorize('BOLD', '════════════════════════════════════════════════════════════════════') . "\n";
    print colorize('CYAN', '  # #####  #  ####    ##    ####   ####   ####                ') . "\n";
    print colorize('CYAN', '  # #    # # #    #  #  #  #      #      #    #               ') . "\n";
    print colorize('CYAN', '  # #    # # #      #    #  ####   ####  #    #               ') . "\n";
    print colorize('CYAN', '  # #####  # #      ######      #      # #    #               ') . "\n";
    print colorize('CYAN', '  # #      # #    # #    # #    # #    # #    #               ') . "\n";
    print colorize('CYAN', '  # #      #  ####  #    #  ####   ####   ####                ') . "\n";
    print colorize('BOLD', '════════════════════════════════════════════════════════════════════') . "\n";
    print "\n";
    
    print_status("Scanning directory: $src_dir");
    
    # First pass: collect all image files
    my @image_files;
    find({
        wanted => sub {
            push @image_files, $File::Find::name if is_image($_);
        },
        follow => 0,
        no_chdir => 1,
    }, $src_dir);
    
    $stats{total_files} = scalar @image_files;
    
    if ($stats{total_files} == 0) {
        print_warning("No compatible images found");
        exit 0;
    }
    
    # Print configuration summary
    print_status("Found $stats{total_files} image(s) to process");
    print "\n";
    
    print colorize('BOLD', "Configuration:\n");
    print "  " . colorize('CYAN', 'Quality:') . "        $quality";
    print " (lossless)" if $lossless;
    print "\n";
    print "  " . colorize('CYAN', 'Method:') . "        $method\n";
    print "  " . colorize('CYAN', 'Alpha Q:') . "       $alpha_quality\n";
    print "  " . colorize('CYAN', 'File Mode:') . "     $file_mode\n";
    print "  " . colorize('CYAN', 'Output Mode:') . "   $output_mode\n";
    print "  " . colorize('CYAN', 'Output Dir:') . "    $output_dir\n";
    
    if ($file_mode eq 'move') {
        print "  " . colorize('CYAN', 'Move To:') . "       $move_folder\n";
    }
    if ($backup_enabled || $file_mode eq 'backup') {
        print "  " . colorize('CYAN', 'Backup Dir:') . "   $backup_dir\n";
    }
    if ($resize_enabled) {
        print "  " . colorize('CYAN', 'Resizing:') . "     ";
        if ($resize_width && $resize_height) {
            print "${resize_width}x${resize_height}\n";
        } elsif ($resize_max) {
            print "max ${resize_max}px\n";
        }
    }
    
    print "  " . colorize('CYAN', 'Parallel:') . "      $max_children workers\n";
    
    if ($file_mode eq 'delete' || $delete_originals) {
        print "\n";
        print colorize('YELLOW', "⚠ WARNING: Original files will be DELETED after conversion!\n");
    }
    
    print "\n";
    
    # Create output directory
    make_path($output_dir) unless -d $output_dir;
    
    # Create backup directory if needed
    if ($backup_enabled || $file_mode eq 'backup') {
        make_path($backup_dir) unless -d $backup_dir;
    }
    
    # Create move directory if needed
    if ($file_mode eq 'move' && $move_folder) {
        my $move_dir = File::Spec->catdir($src_dir, $move_folder);
        make_path($move_dir) unless -d $move_dir;
    }
    
    # Setup progress bar
    my $progress;
    if ($has_progress_bar && !$verbose) {
        $progress = Term::ProgressBar->new({
            name   => 'Converting',
            count  => $stats{total_files},
            ETA    => 'linear',
            fh     => \*STDOUT,
            remove => 0,
        });
        $progress->minor(0);
    }
    
    my $processed = 0;
    my $next_update = 0;
    
    # Process files
    foreach my $src_file (@image_files) {
        # Parallel processing
        if ($max_children > 1 && $running_children >= $max_children) {
            wait_for_child();
        }
        
        if ($max_children > 1) {
            my $pid = fork();
            if (!defined $pid) {
                die "Failed to fork: $!\n";
            } elsif ($pid == 0) {
                # Child process
                process_file($src_file, $output_dir, $backup_dir, $src_dir);
                exit(0);
            } else {
                # Parent process
                push @child_pids, $pid;
                $running_children++;
                reap_zombies();
            }
        } else {
            # Sequential processing
            process_file($src_file, $output_dir, $backup_dir, $src_dir);
        }
        
        $processed++;
        
        # Update progress bar
        if ($progress && $processed >= $next_update) {
            $next_update = $progress->update($processed);
        }
    }
    
    # Wait for all children to finish
    wait_for_all_children();
    
    # Final progress update
    if ($progress) {
        $progress->update($stats{total_files});
    }
    
    # Calculate final statistics
    $stats{end_time} = time();
    my $elapsed = $stats{end_time} - $stats{start_time};
    my $size_saved = $stats{original_size} - $stats{converted_size};
    my $compression_ratio = 0;
    if ($stats{original_size} > 0) {
        $compression_ratio = ($stats{converted_size} / $stats{original_size}) * 100;
    }
    
    # Print summary
    print "\n\n";
    print colorize('BOLD', '════════════════════════════════════════════════════════════════════') . "\n";
    print colorize('CYAN', '  # #####  #  ####    ##    ####   ####   ####                ') . "\n";
    print colorize('CYAN', '  # #    # # #    #  #  #  #      #      #    #               ') . "\n";
    print colorize('CYAN', '  # #    # # #      #    #  ####   ####  #    #               ') . "\n";
    print colorize('CYAN', '  # #####  # #      ######      #      # #    #               ') . "\n";
    print colorize('CYAN', '  # #      # #    # #    # #    # #    # #    #               ') . "\n";
    print colorize('CYAN', '  # #      #  ####  #    #  ####   ####   ####                ') . "\n";
    print colorize('BOLD', '════════════════════════════════════════════════════════════════════') . "\n";
    print "\n";
    
    print "  " . colorize('GREEN', 'Files Processed:') . "    $stats{total_files}\n";
    print "  " . colorize('GREEN', 'Converted:') . "          $stats{converted}\n";
    
    if ($stats{skipped} > 0) {
        print "  " . colorize('YELLOW', 'Skipped:') . "            $stats{skipped}\n";
    }
    
    if ($stats{failed} > 0) {
        print "  " . colorize('RED', 'Failed:') . "              $stats{failed}\n";
    }
    
    print "\n";
    print "  " . colorize('CYAN', 'Original Size:') . "      " . format_size($stats{original_size}) . "\n";
    print "  " . colorize('CYAN', 'Converted Size:') . "     " . format_size($stats{converted_size}) . "\n";
    
    if ($size_saved > 0) {
        print "  " . colorize('GREEN', 'Space Saved:') . "        " . format_size($size_saved) . "\n";
    } elsif ($size_saved < 0) {
        print "  " . colorize('YELLOW', 'Size Increase:') . "      " . format_size(-$size_saved) . "\n";
    }
    
    print "  " . colorize('GREEN', 'Compression Ratio:') . "  " . sprintf("%.1f%%", $compression_ratio) . "\n";
    
    print "\n";
    print "  " . colorize('MAGENTA', 'Time Elapsed:') . "      " . format_time($elapsed) . "\n";
    
    if ($elapsed > 0) {
        print "  " . colorize('MAGENTA', 'Speed:') . "             " . sprintf("%.1f files/sec", $stats{total_files} / $elapsed) . "\n";
    }
    
    print "\n";
    print "  " . colorize('BOLD', 'Output Location:') . "    $output_dir\n";
    
    if ($backup_enabled || $file_mode eq 'backup') {
        print "  " . colorize('BOLD', 'Backup Location:') . "    $backup_dir\n";
    }
    
    if ($file_mode eq 'move' && $move_folder) {
        my $moved_dir = File::Spec->catdir($src_dir, $move_folder);
        print "  " . colorize('BOLD', 'Moved To:') . "          $moved_dir\n";
    }
    
    print "\n";
    
    # File mode summary
    if ($stats{file_modes}{deleted} > 0) {
        print "  " . colorize('RED', 'Files Deleted:') . "      $stats{file_modes}{deleted}\n";
    }
    if ($stats{file_modes}{moved} > 0) {
        print "  " . colorize('YELLOW', 'Files Moved:') . "        $stats{file_modes}{moved}\n";
    }
    if ($stats{file_modes}{backed_up} > 0) {
        print "  " . colorize('CYAN', 'Files Backed Up:') . "    $stats{file_modes}{backed_up}\n";
    }
    if ($stats{file_modes}{preserved} > 0) {
        print "  " . colorize('GREEN', 'Files Preserved:') . "     $stats{file_modes}{preserved}\n";
    }
    
    print "\n";
    print colorize('BOLD', '════════════════════════════════════════════════════════════════════') . "\n";
    
    # Exit with error code if any failures
    exit($stats{failed} > 0 ? 1 : 0);
}

# Run main
main();

__END__

=head1 NAME

picasso_engine.pl - PICASSO WebP Conversion Engine v2.0

=head1 SYNOPSIS

 picasso_engine.pl <directory> [options...]

=head1 DESCRIPTION

Full-featured conversion engine supporting:

=over 4

=item * Multiple output modes (subfolder, same_directory, custom_path, flatten)

=item * Flexible file handling (preserve, delete, move, backup)

=item * Image resizing

=item * Metadata control

=item * Lossless mode

=item * WebP optimization

=item * Parallel processing

=back

=head1 OPTIONS

 All options are passed as positional arguments. See the script for the full list.

=cut

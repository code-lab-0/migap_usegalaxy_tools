#!/usr/bin/perl

use strict;
use warnings;
use JSON qw/decode_json/;
use IPC::Cmd qw/can_run run run_forked/;

my $INPUT = shift @ARGV;
my $OUTPUT = shift @ARGV;
my $USER = shift @ARGV;
my $PW = shift @ARGV;
my $OPTIONS = join(" ", @ARGV);

my $CONTAINER_ID = `cat /proc/1/cpuset`;
chomp $CONTAINER_ID;
$CONTAINER_ID =~ s/.*\///;

my $DATA_DIR = $INPUT;
my $INPUT_FNAME = $INPUT;
$INPUT_FNAME =~ s/.*\///;

my $REMOTE_BLAST_DB_DIR = "/home/okuda/data/db/cog/20030417";
my $BLAST_DB = "myva";
my $REMOTE_DATA_DIR = "/home/$USER/gw_dir/$CONTAINER_ID";

my $GW_DATA_DIR = "/home/$USER/gw_dir/$CONTAINER_ID";
my $GW = "172.19.24.113";

my $OUTPUT_FNAME = $OUTPUT;
$OUTPUT_FNAME =~ s/.*\///;

my $SCRIPT_PREFIX = 'cog-search';
my $SPRIT_SEQ_NUM = 1000;
my $THREAD_NUM = 4;
my $IMG = "yookuda/blast_plus";

&main;
exit;

sub main {
    # split fasta file
    my ($file_count, $total_file_count) = &split_fasta_file;

    # copy files to UGE cluster
    &scp_files($total_file_count);

    # post job
    my $i = 0;
    my @job_ids = ();
    while ($i <= $total_file_count) {
        my $job_id = &post_job($i, $total_file_count);
        if ($job_id =~ /^\d+$/) {
            push @job_ids, $job_id;
        }
        ++$i;
    }

    # check job state
    my $job_state = 1;
    while ($job_state) {
        sleep(60);
        $job_state = &check_job_state(\@job_ids);
    }

    # copy files from UGE cluster
    my $j = 0;
    while ($j <= $total_file_count) {
        my $cmd = "sh -c \"sshpass -p '$PW' scp -o StrictHostKeyChecking=no $USER\@$GW:$GW_DATA_DIR/$OUTPUT_FNAME.$j $OUTPUT.$j\"";
        &check_cmd_result($cmd, "copy result file $j");
        `cat $OUTPUT.$j >> $OUTPUT`;
        ++$j;
    }

#    &remove_files($total_file_count);
}

sub check_cmd_result {
    my $cmd = $_[0];
    my $label = $_[1];
    while (1) {
        my ($success, $error_msg, $full_buf, $stdout_buf, $stderr_buf) = run(command => $cmd, verbose => 0);
        if ($success) {
            print "$label:stdout:@$stdout_buf\n";
            print "$label:stderr:@$stderr_buf\n";
            return $stdout_buf;
        } else {
            print "$label:error_msg:$error_msg\n";
        }
        sleep(60);
    }

}

# split fasta file
sub split_fasta_file {
    my $seq_count = 0;
    my $file_count = 0;
    my $total_file_count = 0;
    open DATA, $INPUT or die;
    while (<DATA>) {
        ++$seq_count if /^>/;
    }
    close DATA;

    if ($seq_count % $SPRIT_SEQ_NUM == 0) {
        $total_file_count = $seq_count / $SPRIT_SEQ_NUM - 1;
    } else {
        $total_file_count = ($seq_count - ($seq_count % $SPRIT_SEQ_NUM)) / $SPRIT_SEQ_NUM;
    }

    $seq_count = 0;

    open DATA, $INPUT or die;
    open OUT, ">$INPUT.${SCRIPT_PREFIX}_${file_count}_${total_file_count}" or die;

    &create_remote_command_script($file_count, $total_file_count);

    while (<DATA>) {
        if (/^>/) {
            ++$seq_count;
            if ($seq_count == $SPRIT_SEQ_NUM) {
                close OUT;
                ++$file_count;
                $seq_count = 0;
                open OUT, ">$INPUT.${SCRIPT_PREFIX}_${file_count}_${total_file_count}" or die;

                &create_remote_command_script($file_count, $total_file_count);

            }
        }
        print OUT $_;
    }
    close DATA;
    return($file_count, $total_file_count);
}

# create remote command script
sub create_remote_command_script {
    my $file_count = $_[0];
    my $total_file_count = $_[1];
    my $script = "${OUTPUT}.$SCRIPT_PREFIX.${file_count}_${total_file_count}.sh";

    open SCRIPT, ">$script" or die;

    print SCRIPT '#!/bin/sh', "\n";
    print SCRIPT '#$ -S /bin/sh', "\n";
    print SCRIPT '#$ -cwd', "\n";
    print SCRIPT 'docker run \\', "\n";
    print SCRIPT "-v $REMOTE_DATA_DIR:/data \\", "\n";
    print SCRIPT "-v $REMOTE_BLAST_DB_DIR:/db \\", "\n";
    print SCRIPT "--rm \\", "\n";
    print SCRIPT "$IMG \\", "\n";
    print SCRIPT "/usr/local/bin/blastp \\", "\n";
    print SCRIPT "-db /db/$BLAST_DB \\", "\n";
    print SCRIPT "-query /data/$INPUT_FNAME.${SCRIPT_PREFIX}_${file_count}_${total_file_count} \\", "\n";
    print SCRIPT "-out /data/$OUTPUT_FNAME.${file_count} \\", "\n";
    print SCRIPT '-outfmt "0" \\', "\n";
    print SCRIPT "$OPTIONS \\", "\n";
    print SCRIPT "-num_threads $THREAD_NUM", "\n";

    my $ret2 = chmod 0755, $script;
}

sub scp_files {
    my $total_file_count = $_[0];

    # create gateway data directory
    my $cmd1 = "sh -c \"sshpass -p '$PW' ssh -o StrictHostKeyChecking=no $USER\@$GW 'if [ ! -e $GW_DATA_DIR ]; then mkdir -p $GW_DATA_DIR ; fi'\"";

    &check_cmd_result($cmd1, 'create gateway data directory');

    my $i = 0;
    my $script;
    my $input_file;

    while ($i <= $total_file_count) {
        $script = "$OUTPUT.$SCRIPT_PREFIX.${i}_${total_file_count}.sh";
        $input_file = "$INPUT.${SCRIPT_PREFIX}_${i}_${total_file_count}";

        # copy remote command script
        my $cmd2 = "sh -c \"sshpass -p '$PW' scp -o StrictHostKeyChecking=no -p $script $USER\@$GW:$GW_DATA_DIR\"";
        &check_cmd_result($cmd2, "scp script file $i");

        # copy data file
        my $cmd3 = "sh -c \"sshpass -p '$PW' scp -o StrictHostKeyChecking=no $input_file $USER\@$GW:$GW_DATA_DIR\"";
        &check_cmd_result($cmd3, "scp data file $i");

        ++$i;
    }
}

sub remove_files {
    my $total_file_count = $_[0];

    my $i = 0;
    my $script;
    my $input_file;

    while ($i <= $total_file_count) {
#        my $cmd1 = "sudo -u $USER sh -c \"ssh -i $ID_RSA $USER\@$GW 'rm $GW_DATA_DIR/$SCRIPT_PREFIX.${i}_${total_file_count}.sh'\"";
#        &check_cmd_result($cmd1, "remove gw script file $i");

#        my $cmd2 = "sudo -u $USER sh -c \"ssh -i $ID_RSA $USER\@$GW 'rm $GW_DATA_DIR/$INPUT_FNAME.${SCRIPT_PREFIX}_${i}_${total_file_count}'\"";
#        &check_cmd_result($cmd2, "remove gw data file $i");

#        my $cmd3 = "rm $USER_DATA_DIR/$SCRIPT_PREFIX.${i}_${total_file_count}.sh";
#        &check_cmd_result($cmd3, "remove script file $i from user data dir");

#        my $cmd4 = "rm $USER_DATA_DIR/$INPUT_FNAME.${SCRIPT_PREFIX}_${i}_${total_file_count}";
#        &check_cmd_result($cmd4, "remove data file $i from user data dir");

#        my $cmd5 = "rm $USER_DATA_DIR/$OUTPUT_FNAME.$i";
#        &check_cmd_result($cmd5, "remove output file $i from user data dir");

        ++$i;
    }
}

sub post_job {
    my $file_count = $_[0];
    my $total_file_count = $_[1];

    my $script = "$REMOTE_DATA_DIR/$OUTPUT_FNAME.$SCRIPT_PREFIX.${file_count}_${total_file_count}.sh";
    my $cmd = "curl -s -X POST -H 'Content-Type:application/json' http://$GW:8182/jobs -d '{\"remoteCommand\":\"$script\", \"args\":[], \"nativeSpecification\":\"-pe def_slot $THREAD_NUM\"}' -u $USER:$PW";
    my $stdout_buf = &check_cmd_result($cmd, "post job $file_count");

    my $job_id = join('', @$stdout_buf);
    my $job_id_json = decode_json($job_id);
    if ($job_id_json->{"jobid"}) {
        $job_id = $job_id_json->{"jobid"};
    } else {
        print STDERR "$job_id\n";
        exit;
    }
    return $job_id;
}

sub check_job_state {
    my $job_ids = $_[0];
    my @job_ids = @$job_ids;

    my $cmd = "curl -s -X GET -H 'Content-Type: application/json' http://$GW:8182/jobs -u $USER:$PW";

    my $stdout_buf = &check_cmd_result($cmd, 'check job state');

    my $result = join('', @$stdout_buf);
    my $result_json = decode_json($result);

    # job list is empty.
    my $length = @$result_json;
    if ($length == 0) {
        foreach my $job_id (@job_ids) {
            my $cmd = "curl -s -X GET -H 'Content-Type: application/json' http://$GW:8182/jobs/$job_id -u $USER:$PW";
            my $stdout_buf = &check_cmd_result($cmd, "check job $job_id state");
            my $result = join('', @$stdout_buf);
            my $result_json = decode_json($result);
            if ($result_json->{'errorMessage'} ne "Job '$job_id' not found.") {
                return 1;
            }
        }
        return 0;
    }

    foreach my $job_id (@$result_json) {
        $job_id =~ s/\.\d$//;
        foreach my $posted_job_id (@job_ids) {
            return 1 if $job_id == $posted_job_id;
        }
    }
    return 0;
}


#!/usr/bin/perl

use strict;
use warnings;
use JSON qw/decode_json/;
use IPC::Cmd qw/can_run run run_forked/;

&main;
exit;

sub main {
    my %pref = ();
    my $pref_ref = \%pref;

    $pref{'INPUT'} = shift @ARGV;
    $pref{'OUTPUT'} = shift @ARGV;
    $pref{'USER'} = shift @ARGV;
    $pref{'PW'} = shift @ARGV;
    $pref{'OPTIONS'} = join(" ", @ARGV);

    my $CONTAINER_ID = `cat /proc/1/cpuset`;
    chomp $CONTAINER_ID;
    $CONTAINER_ID =~ s/.*\///;
    $pref{'CONTAINER_ID'} = $CONTAINER_ID;
    
    my $INPUT_FNAME = $pref{'INPUT'};
    $INPUT_FNAME =~ s/.*\///;
    $pref{'INPUT_FNAME'} = $INPUT_FNAME;

    my $OUTPUT_FNAME = $pref{'OUTPUT'};
    $OUTPUT_FNAME =~ s/.*\///;
    $pref{'OUTPUT_FNAME'} = $OUTPUT_FNAME;

    $pref{'REMOTE_BLAST_DB_DIR'} = '/home/okuda/data/db/cog/20030417';
    $pref{'BLAST_DB'} = 'myva';
    $pref{'REMOTE_DATA_DIR'} = "/home/$pref{'USER'}/gw_dir/$CONTAINER_ID";

    $pref{'GW_DATA_DIR'} = "/home/$pref{'USER'}/gw_dir/$CONTAINER_ID";
    $pref{'GW'} = '172.19.24.113';

    $pref{'SCRIPT_PREFIX'} = 'cog-search';
    $pref{'SPRIT_SEQ_NUM'} = 1000;
    $pref{'THREAD_NUM'} = 4;
    $pref{'IMG'} = 'yookuda/blast_plus';

    # split fasta file
    my ($file_count, $total_file_count) = &split_fasta_file($pref_ref);

    # copy files to UGE cluster
    &scp_files($total_file_count, $pref_ref);

    # post job
    my $i = 0;
    my @job_ids = ();
    while ($i <= $total_file_count) {
        my $job_id = &post_job($i, $total_file_count, $pref_ref);
        if ($job_id =~ /^\d+$/) {
            push @job_ids, $job_id;
        }
        ++$i;
    }

    # check job state
    my $job_state = 1;
    while ($job_state) {
        sleep(60);
        $job_state = &check_job_state(\@job_ids, $pref_ref);
    }

    # copy files from UGE cluster
    &get_result($total_file_count, $pref_ref);

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
    my $pref_ref = $_[0];
    my $INPUT = $$pref_ref{'INPUT'};
    my $SPRIT_SEQ_NUM = $$pref_ref{'SPRIT_SEQ_NUM'};
    my $SCRIPT_PREFIX = $$pref_ref{'SCRIPT_PREFIX'};

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

    &create_remote_command_script($file_count, $total_file_count, $pref_ref);

    while (<DATA>) {
        if (/^>/) {
            ++$seq_count;
            if ($seq_count == $SPRIT_SEQ_NUM) {
                close OUT;
                ++$file_count;
                $seq_count = 0;
                open OUT, ">$INPUT.${SCRIPT_PREFIX}_${file_count}_${total_file_count}" or die;

                &create_remote_command_script($file_count, $total_file_count, $pref_ref);

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
    my $pref_ref = $_[2];

    my $OUTPUT = $$pref_ref{'OUTPUT'};
    my $SCRIPT_PREFIX = $$pref_ref{'SCRIPT_PREFIX'};
    my $script = "${INPUT}.$SCRIPT_PREFIX.${file_count}_${total_file_count}.sh";
    my $REMOTE_DATA_DIR = $$pref_ref{'REMOTE_DATA_DIR'};
    my $REMOTE_BLAST_DB_DIR = $$pref_ref{'REMOTE_BLAST_DB_DIR'};
    my $IMG = $$pref_ref{'IMG'};
    my $BLAST_DB = $$pref_ref{'BLAST_DB'};
    my $INPUT_FNAME = $$pref_ref{'INPUT_FNAME'};
    my $OUTPUT_FNAME = $$pref_ref{'OUTPUT_FNAME'};
    my $OPTIONS = $$pref_ref{'OPTIONS'};
    my $THREAD_NUM = $$pref_ref{'THREAD_NUM'};

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
    my $pref_ref = $_[1];

    my $PW = $$pref_ref{'PW'};
    my $USER = $$pref_ref{'USER'};
    my $GW = $$pref_ref{'GW'};
    my $GW_DATA_DIR = $$pref_ref{'GW_DATA_DIR'};
    my $SCRIPT_PREFIX = $$pref_ref{'SCRIPT_PREFIX'};
    my $INPUT = $$pref_ref{'INPUT'};

    # create gateway data directory
    my $cmd1 = "sh -c \"sshpass -p '$PW' ssh -o StrictHostKeyChecking=no $USER\@$GW 'if [ ! -e $GW_DATA_DIR ]; then mkdir -p $GW_DATA_DIR ; fi'\"";

    &check_cmd_result($cmd1, 'create gateway data directory');

    my $i = 0;
    my $script;
    my $input_file;

    while ($i <= $total_file_count) {
        $script = "$INPUT.$SCRIPT_PREFIX.${i}_${total_file_count}.sh";
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
    my $pref_ref = $_[2];

    my $REMOTE_DATA_DIR = $$pref_ref{'REMOTE_DATA_DIR'};
    my $INPUT_FNAME = $$pref_ref{'INPUT_FNAME'};
    my $SCRIPT_PREFIX = $$pref_ref{'SCRIPT_PREFIX'};
    my $GW = $$pref_ref{'GW'};
    my $THREAD_NUM = $$pref_ref{'THREAD_NUM'};
    my $USER = $$pref_ref{'USER'};
    my $PW = $$pref_ref{'PW'};

    my $script = "$REMOTE_DATA_DIR/$INPUT_FNAME.$SCRIPT_PREFIX.${file_count}_${total_file_count}.sh";
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
    my $pref_ref = $_[1];

    my $GW = $$pref_ref{'GW'};
    my $USER = $$pref_ref{'USER'};
    my $PW = $$pref_ref{'PW'};

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


# copy files from UGE cluster
sub get_result {
    my $total_file_count = $_[0];
    my $pref_ref = $_[1];

    my $USER = $$pref_ref{'USER'};
    my $PW = $$pref_ref{'PW'};
    my $GW = $$pref_ref{'GW'};
    my $GW_DATA_DIR = $$pref_ref{'GW_DATA_DIR'};
    my $OUTPUT_FNAME = $$pref_ref{'OUTPUT_FNAME'};
    my $OUTPUT = $$pref_ref{'OUTPUT'};

    my $i = 0;
    while ($i <= $total_file_count) {
        my $cmd = "sh -c \"sshpass -p '$PW' scp -o StrictHostKeyChecking=no $USER\@$GW:$GW_DATA_DIR/$OUTPUT_FNAME.$i $OUTPUT.$i\"";
        &check_cmd_result($cmd, "copy result file $i");
        `cat $OUTPUT.$i >> $OUTPUT`;
        ++$i;
    }
}

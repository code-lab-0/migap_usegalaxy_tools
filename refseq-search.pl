#!/usr/bin/perl

use strict;
use warnings;
use JSON qw/decode_json/;
use IPC::Cmd qw/can_run run run_forked/;

&main;
exit;

sub main {
    my $pref_ref = &set_pref;

    # split fasta file and create job scripts.
    my $total_file_count = &split_fasta_file($pref_ref);

    # copy files to UGE cluster
    &scp_files($total_file_count, $pref_ref);

    # post job
    my $job_ids_ref = &post_job($total_file_count, $pref_ref);

    # check job state
    my $job_state = 1;
    while ($job_state) {
        sleep(60);
        $job_state = &check_job_state($job_ids_ref, $pref_ref);
    }

    # copy files from UGE cluster
    &get_result($total_file_count, $pref_ref);

#    &remove_files($total_file_count);
}

# 定数の設定
sub set_pref {
    my %pref = ();
    my $pref_ref = \%pref;

    $pref{'INPUT'} = shift @ARGV;
    $pref{'OUTPUT'} = shift @ARGV;
    $pref{'USER'} = shift @ARGV;
    $pref{'PW'} = shift @ARGV;
    $pref{'OPTIONS'} = join(" ", @ARGV);

    my $INPUT_FNAME = $pref{'INPUT'};
    $INPUT_FNAME =~ s/.*\///;
    $pref{'INPUT_FNAME'} = $INPUT_FNAME;

    my $OUTPUT_FNAME = $pref{'OUTPUT'};
    $OUTPUT_FNAME =~ s/.*\///;
    $pref{'OUTPUT_FNAME'} = $OUTPUT_FNAME;

    # このスクリプトが実行されるgalaxyコンテナのcontainer id
    my $CONTAINER_ID = `cat /proc/1/cpuset`;
    chomp $CONTAINER_ID;
    $CONTAINER_ID =~ s/.*\///;
    $pref{'CONTAINER_ID'} = $CONTAINER_ID;

    # UGEで実行されるBLAST検索で使用するBLAST DB    
    $pref{'REMOTE_BLAST_DB_DIR'} = '/home/okuda/data/db/refseq_protein/20140911';
    $pref{'BLAST_DB'} = 'microbial.protein';

    # UGEで実行されるジョブのデータ・スクリプトを置くディレクトリ
    $pref{'REMOTE_DATA_DIR'} = "/home/$pref{'USER'}/gw_dir/$CONTAINER_ID";

    # galaxyコンテナからUGE REST ServiceにアクセスするためのURL
    $pref{'UGE_REST_URL'} = '172.19.24.113';
    $pref{'UGE_REST_PORT'} = '8182';

    # UGEの前にゲートウェイがある場合に$pref{'REMOTE_DATA_DIR'}がマウントされているディレクトリ
    # ゲートウェイがない場合は$pref{'REMOTE_DATA_DIR'}と同じ値を入れる。
    $pref{'GW_DATA_DIR'} = "/home/$pref{'USER'}/gw_dir/$CONTAINER_ID";

    $pref{'SCRIPT_PREFIX'} = 'refseq-search';

    # 1ジョブ当たりの配列数
    $pref{'SPRIT_SEQ_NUM'} = 100;

    # 1ジョブに割り当てるスレッド数
    $pref{'THREAD_NUM'} = 4;

    # BLAST dockerイメージ
    $pref{'IMG'} = 'yookuda/blast_plus';

    return $pref_ref;
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

# 入力FASTAファイルを$pref{'SPRIT_SEQ_NUM'}ずつ分割する。
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
    return $total_file_count;
}

# 分割されたFASTAファイルごとにジョブスクリプトを生成する。
sub create_remote_command_script {
    my $file_count = $_[0];
    my $total_file_count = $_[1];
    my $pref_ref = $_[2];

    my $INPUT = $$pref_ref{'INPUT'};
    my $SCRIPT_PREFIX = $$pref_ref{'SCRIPT_PREFIX'};
    my $REMOTE_DATA_DIR = $$pref_ref{'REMOTE_DATA_DIR'};
    my $REMOTE_BLAST_DB_DIR = $$pref_ref{'REMOTE_BLAST_DB_DIR'};
    my $IMG = $$pref_ref{'IMG'};
    my $BLAST_DB = $$pref_ref{'BLAST_DB'};
    my $INPUT_FNAME = $$pref_ref{'INPUT_FNAME'};
    my $OUTPUT_FNAME = $$pref_ref{'OUTPUT_FNAME'};
    my $OPTIONS = $$pref_ref{'OPTIONS'};
    my $THREAD_NUM = $$pref_ref{'THREAD_NUM'};

    my $script = "${INPUT}.$SCRIPT_PREFIX.${file_count}_${total_file_count}.sh";

    open SCRIPT, ">$script" or die;
    print SCRIPT <<"SCRIPT";
#!/bin/sh
#$ -S /bin/sh
#$ -cwd
docker run \\
    -v $REMOTE_DATA_DIR:/data \\
    -v $REMOTE_BLAST_DB_DIR:/db \\
    --rm \\
    $IMG \\
    /usr/local/bin/blastp \\
        -db /db/$BLAST_DB \\
        -query /data/$INPUT_FNAME.${SCRIPT_PREFIX}_${file_count}_${total_file_count} \\
        -out /data/$OUTPUT_FNAME.${file_count} \\
        -outfmt "0" \\
        $OPTIONS \\
        -num_threads $THREAD_NUM
SCRIPT

    my $ret2 = chmod 0755, $script;
}

# FASTAファイル・ジョブスクリプトをUGEクラスタにコピーする。
sub scp_files {
    my $total_file_count = $_[0];
    my $pref_ref = $_[1];

    my $PW = $$pref_ref{'PW'};
    my $USER = $$pref_ref{'USER'};
    my $UGE_REST_URL = $$pref_ref{'UGE_REST_URL'};
    my $GW_DATA_DIR = $$pref_ref{'GW_DATA_DIR'};
    my $SCRIPT_PREFIX = $$pref_ref{'SCRIPT_PREFIX'};
    my $INPUT = $$pref_ref{'INPUT'};

    # create gateway data directory
    my $cmd1 = "sh -c \"sshpass -p '$PW' ssh -o StrictHostKeyChecking=no $USER\@$UGE_REST_URL 'if [ ! -e $GW_DATA_DIR ]; then mkdir -p $GW_DATA_DIR ; fi'\"";

    &check_cmd_result($cmd1, 'create gateway data directory');

    my $i = 0;
    my $script;
    my $input_file;

    while ($i <= $total_file_count) {
        $script = "$INPUT.$SCRIPT_PREFIX.${i}_${total_file_count}.sh";
        $input_file = "$INPUT.${SCRIPT_PREFIX}_${i}_${total_file_count}";

        # copy remote command script
        my $cmd2 = "sh -c \"sshpass -p '$PW' scp -o StrictHostKeyChecking=no -p $script $USER\@$UGE_REST_URL:$GW_DATA_DIR\"";
        &check_cmd_result($cmd2, "scp script file $i");

        # copy data file
        my $cmd3 = "sh -c \"sshpass -p '$PW' scp -o StrictHostKeyChecking=no $input_file $USER\@$UGE_REST_URL:$GW_DATA_DIR\"";
        &check_cmd_result($cmd3, "scp data file $i");

        ++$i;
    }
}

sub remove_files {
    my $total_file_count = $_[0];
    my $pref_ref = $_[1];
    my $USER = $$pref_ref{'USER'};
    my $PW = $$pref_ref{'PW'};
    my $UGE_REST_URL = $$pref_ref{'UGE_REST_URL'};
    my $INPUT_FNAME = $$pref_ref{'INPUT_FNAME'};
    my $GW_DATA_DIR = $$pref_ref{'GW_DATA_DIR'};
    my $SCRIPT_PREFIX = $$pref_ref{'SCRIPT_PREFIX'};

    my $i = 0;
    my $script;
    my $input_file;

    while ($i <= $total_file_count) {
        my $cmd1 = "sh -c \"sshpass -p '$PW' ssh -o StrictHostKeyChecking=no $USER\@$UGE_REST_URL 'rm $GW_DATA_DIR/$INPUT_FNAME.$SCRIPT_PREFIX.${i}_${total_file_count}.sh'\"";
        &check_cmd_result($cmd1, "remove gw script file $i");

        my $cmd2 = "sh -c \"sshpass -p '$PW' ssh -o StrictHostKeyChecking=no $USER\@$UGE_REST_URL 'rm $GW_DATA_DIR/$INPUT_FNAME.${SCRIPT_PREFIX}_${i}_${total_file_count}'\"";
        &check_cmd_result($cmd2, "remove gw data file $i");

        ++$i;
    }
}

# UGE REST ServiceにジョブをPOSTしてjob idを取得する。
sub post_job {
    my $total_file_count = $_[0];
    my $pref_ref = $_[1];

    my $REMOTE_DATA_DIR = $$pref_ref{'REMOTE_DATA_DIR'};
    my $INPUT_FNAME = $$pref_ref{'INPUT_FNAME'};
    my $SCRIPT_PREFIX = $$pref_ref{'SCRIPT_PREFIX'};
    my $UGE_REST_URL = $$pref_ref{'UGE_REST_URL'};
    my $UGE_REST_PORT = $$pref_ref{'UGE_REST_PORT'};
    my $THREAD_NUM = $$pref_ref{'THREAD_NUM'};
    my $USER = $$pref_ref{'USER'};
    my $PW = $$pref_ref{'PW'};

    my $file_count = 0;
    my @job_ids = ();
    while ($file_count <= $total_file_count) {
        my $script = "$REMOTE_DATA_DIR/$INPUT_FNAME.$SCRIPT_PREFIX.${file_count}_${total_file_count}.sh";
        my $job_data = "{\"remoteCommand\":\"$script\", \"args\":[], \"nativeSpecification\":\"-pe def_slot $THREAD_NUM\"}";
        my $cmd = "curl -s -X POST -H 'Content-Type:application/json' http://$UGE_REST_URL:$UGE_REST_PORT/jobs -d '$job_data' -u $USER:$PW";

        my $job_id = "";
        my $roop_count = 0;
        while (!$job_id) {
            my $stdout_buf = &check_cmd_result($cmd, "post job $file_count");
            $job_id = join('', @$stdout_buf);
            my $job_id_json = decode_json($job_id);
            if ($job_id_json->{"jobid"}) {
                $job_id = $job_id_json->{"jobid"};
            } else {
                ++$roop_count;
                if ($roop_count > 9) {
                    print STDERR "$job_id\n";
                    exit;
                }
                $job_id = "";
                sleep(10)
            }
        }
        if ($job_id =~ /^\d+$/) {
            push @job_ids, $job_id;
        }
        ++$file_count;
        select(undef, undef, undef, 0.1);
    }
    return \@job_ids;
}

# UGE REST ServiceにPOSTしたジョブがすべて終了するのを監視する。
sub check_job_state {
    my $job_ids = $_[0];
    my @job_ids = @$job_ids;
    my $pref_ref = $_[1];

    my $UGE_REST_URL = $$pref_ref{'UGE_REST_URL'};
    my $UGE_REST_PORT = $$pref_ref{'UGE_REST_PORT'};
    my $USER = $$pref_ref{'USER'};
    my $PW = $$pref_ref{'PW'};

    my $cmd = "curl -s -X GET -H 'Content-Type: application/json' http://$UGE_REST_URL:$UGE_REST_PORT/jobs -u $USER:$PW";

    my $stdout_buf = &check_cmd_result($cmd, 'check job state');

    my $result = join('', @$stdout_buf);
    my $result_json = decode_json($result);

    # job list is empty.
    my $length = @$result_json;
    if ($length == 0) {
        foreach my $job_id (@job_ids) {
            my $cmd = "curl -s -X GET -H 'Content-Type: application/json' http://$UGE_REST_URL:$UGE_REST_PORT/jobs/$job_id -u $USER:$PW";
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


# 終了したジョブの結果を回収する。
sub get_result {
    my $total_file_count = $_[0];
    my $pref_ref = $_[1];

    my $USER = $$pref_ref{'USER'};
    my $PW = $$pref_ref{'PW'};
    my $UGE_REST_URL = $$pref_ref{'UGE_REST_URL'};
    my $GW_DATA_DIR = $$pref_ref{'GW_DATA_DIR'};
    my $OUTPUT_FNAME = $$pref_ref{'OUTPUT_FNAME'};
    my $OUTPUT = $$pref_ref{'OUTPUT'};

    my $i = 0;
    while ($i <= $total_file_count) {
        my $cmd = "sh -c \"sshpass -p '$PW' scp -o StrictHostKeyChecking=no $USER\@$UGE_REST_URL:$GW_DATA_DIR/$OUTPUT_FNAME.$i $OUTPUT.$i\"";
        &check_cmd_result($cmd, "copy result file $i");
        `cat $OUTPUT.$i >> $OUTPUT`;
        ++$i;
    }
}

package App::Uc::TwitterIrcGateway::Plugin::Ctcp::Action;
use 5.014;
use parent 'Uc::IrcGateway::Plugin::Ctcp::Action';
use Uc::IrcGateway::Common;

sub action {
    my $self = shift;
    my ($handle, $msg, $plugin) = @_;
    return unless $self->check_params(@_);

#override '_event_ctcp_action' => sub {
#    my ($self, $handle, $msg) = @_;
#    my ($command, $params) = split(' ', $msg->{params}[0], 2);
#    my @params = $params ? split(' ', $params) : ();
#    my $target = $msg->{target};
#    @{$msg}{qw/command params/} = ($command, \@params);
#
#    given ($command) {
#        when (/$action_command{mention}/) {
#            my %opt;
#            $opt{target}   = $target;
#            $opt{since_id} = $handle->{last_mention_id} if exists $handle->{last_mention_id};
#            $self->get_mentions($handle, %opt);
#        }
#        when (/$action_command{reply}/) {
#            break unless check_params($self, $handle, $msg);
#
#            my ($tid, $text) = split(' ', $params, 2); $text ||= '';
#            break unless $self->check_ngword($handle, $text);
#
#            $self->logger->log();
#            my $tweet_id = $handle->{tmap}->get($tid);
#            my $tweet = $self->logger->{schema}->search('status', { id => $tweet_id })->next;
#            if (!$tweet) {
#                $text = "reply error: no such tid";
#                $self->send_cmd( $handle, $self->daemon, 'NOTICE', $target, "$text [$tid]" );
#            }
#            else {
#                $self->api($handle, 'statuses/update', params => {
#                    status => '@'.$tweet->user->screen_name.' '.$text, in_reply_to_status_id => $tweet->id,
#                }, cb => sub {
#                    my ($header, $res, $reason) = @_;
#                    if (!$res) { $self->send_cmd( $handle, $self->daemon, 'NOTICE', $target,  qq|reply error: "$text": $reason| ); }
#                } );
#            }
#        }
#        when (/$action_command{favorite}/) {
#            break unless check_params($self, $handle, $msg);
#
#            for my $tid (@params) {
#                $self->tid_event($handle, 'favorites/create', $tid, target => $target, cb => sub {
#                    my ($header, $res, $reason) = @_;
#                    $self->logger->remark( $handle, { tid => $tid, favorited => 1 } ) if $res;
#                });
#            }
#        }
#        when (/$action_command{unfavorite}/) {
#            break unless check_params($self, $handle, $msg);
#
#            for my $tid (@params) {
#                $self->tid_event($handle, 'favorites/destroy', $tid, target => $target, cb => sub {
#                    my ($header, $res, $reason) = @_;
#                    $self->logger->remark( $handle, { tid => $tid, favorited => 0 } ) if $res;
#                });
#            }
#        }
#        when (/$action_command{retweet}/) {
#            break unless check_params($self, $handle, $msg);
#
#            for my $tid (@params) {
#                $self->tid_event($handle, 'statuses/retweet/:id', $tid, target => $target, cb => sub {
#                    my ($header, $res, $reason) = @_;
#                    $self->logger->remark( $handle, { tid => $tid, retweeted => 1 } ) if $res;
#                });
#            }
#        }
#        when (/$action_command{quotetweet}/) {
#            break unless check_params($self, $handle, $msg);
#
#            my ($tid, $comment) = split(' ', $params, 2);
#            break unless $self->check_ngword($handle, $comment);
#
#            $self->logger->log();
#            my $tweet_id = $handle->{tmap}->get($tid);
#            my $tweet = $self->logger->{schema}->search('status', { id => $tweet_id })->next;
#            my $text;
#            if (!$tweet) {
#                $text = "quotetweet error: no such tid";
#                $self->send_cmd( $handle, $self->daemon, 'NOTICE', $target, "$text [$tid]" );
#            }
#            else {
#                my $notice = $tweet->text;
#
#                $comment = $comment ? $comment.' ' : '';
#                $text    = $comment.'QT @'.$tweet->user->screen_name.': '.$notice;
#                while (length $text > 140 && $notice =~ /....$/) {
#                    $notice =~ s/....$/.../;
#                    $text   = $comment.'QT @'.$tweet->user->screen_name.': '.$notice;
#                }
#
#                $self->api($handle, 'statuses/update', params => {
#                    status => $text, in_reply_to_status_id => $tweet->id,
#                }, cb => sub {
#                    my ($header, $res, $reason) = @_;
#                    if (!$res) { $self->send_cmd( $handle, $self->daemon, 'NOTICE', $target, qq|quotetweet error: "$text": $reason| ); }
#                } );
#            }
#        }
#        when (/$action_command{delete}/) {
#            my @tids = @params;
#               @tids = $handle->get_channels($handle->options->{stream})->topic =~ /\[(.+?)\]$/ if not scalar @tids;
#
#            break if not scalar @tids;
#            for my $tid (@tids) {
#                $self->tid_event($handle, 'statuses/destroy/:id', $tid, target => $target);
#            }
#        }
#        when (/$action_command{list}/) {
#            break unless check_params($self, $handle, $msg);
#
#            $self->api($handle, 'statuses/user_timeline', params => { screen_name => $params[0] }, cb => sub {
#                my ($header, $res, $reason) = @_;
#                if ($res) {
#                    my $tweets = $res;
#                    for my $tweet (reverse @$tweets) {
#                        $self->process_tweet($handle, tweet => $tweet, target => $target, notice => 1);
#                    }
#                }
#                else { $self->send_cmd( $handle, $self->daemon, 'NOTICE', $target, qq|list action error: $reason| ); }
#            });
#        }
#        when (/$action_command{information}/) {
#            break unless check_params($self, $handle, $msg);
#
#            for my $tid (@params) {
#                my $text;
#                my $tweet_id = $handle->{tmap}->get($tid);
#                if (!$tweet_id) {
#                    $text = "information error: no such tid";
#                    $self->send_cmd( $handle, $self->daemon, 'NOTICE', $target, "$text [$tid]" );
#                }
#                else {
#                    $self->api($handle, "statuses/show/$tweet_id", cb => sub {
#                        my ($header, $res, $reason) = @_;
#                        if ($res) {
#                            my $tweet = $res;
#                            $text  = "information: $tweet->{user}{screen_name}: retweet count $tweet->{retweet_count}: source $tweet->{source}";
#                            $text .= ": conversation" if $tweet->{in_reply_to_status_id};
#                            $self->send_cmd( $handle, $self->daemon, 'NOTICE', $target, "$text ($tweet->{created_at}) [$tid]" );
#                        }
#                        else { $self->send_cmd( $handle, $self->daemon, 'NOTICE', $target, qq|information action error: $reason| ); }
#                    });
#                }
#            }
#        }
#        when (/$action_command{conversation}/) {
#            break unless check_params($self, $handle, $msg);
#
#            $self->logger->log();
#            my $tid = $params[0];
#            my $tweet_id = $handle->{tmap}->get($tid);
#            my @statuses;
#            my $limit = 10;
#            my $cb; $cb = sub {
#                my ($header, $res, $reason) = @_;
#                my $conversation = 0;
#
#                if ($res) {
#                    $conversation = 1 if $res->{in_reply_to_status_id};
#                    push @statuses, $res;
#                }
#                else {
#                    $self->send_cmd( $handle, $self->daemon, 'NOTICE', $target, qq|conversation error: $reason| );
#                }
#
#                if (--$limit > 0 && $conversation) {
#                    $self->api($handle, 'statuses/show/'.$res->{in_reply_to_status_id}, cb => $cb);
#                }
#                else {
#                    $self->send_cmd( $handle, $self->daemon, 'NOTICE', $target,
#                        "conversation: there are more conversation before" ) if $limit <= 0;
#                    for my $status (reverse @statuses) {
#                        $self->process_tweet($handle, tweet =>  $status, target => $target, notice => 1);
#                    }
#                }
#            };
#
#            if (!$tweet_id) {
#                my $text;
#                $text = "conversation error: no such tid";
#                $self->send_cmd( $handle, $self->daemon, 'NOTICE', $target, "$text [$tid]" );
#            }
#            else {
#                $self->api($handle, 'statuses/show/'.$tweet_id, cb => $cb);
#            }
#        }
#        when (/$action_command{ratelimit}/) {
#            $self->api($handle, 'account/rate_limit_status', params => { screen_name => $params[0] }, cb => sub {
#                my ($header, $res, $reason) = @_;
#                my $text;
#                if (!$res) {
#                    $text = "ratelimit error: $reason";
#                }
#                else {
#                    my $limit = $res;
#                    $text  = "ratelimit: remaining hits $limit->{remaining_hits}/$limit->{hourly_limit}";
#                    $text .= ": reset time $limit->{reset_time}" if $limit->{remaining_hits} <= 0;
#                }
#                $self->send_cmd( $handle, $self->daemon, 'NOTICE', $target, $text);
#            });
#        }
#        when (/$action_command{ngword}/) {
#            my $text = "ngword:";
#            my $ngword = lc $params;
#            if ($params) {
#                if (exists $handle->{ngword}{$ngword}) {
#                    delete $handle->{ngword}{$ngword};
#                    $text .= qq| -"$ngword"|;
#                }
#                else {
#                    $handle->{ngword}{$ngword} = 1;
#                    $text .= qq| +"$ngword"|;
#                }
#                $self->send_cmd( $handle, $self->daemon, 'NOTICE', $target, $text );
#            }
#            else {
#                $self->send_cmd( $handle, $self->daemon, 'NOTICE', $target, qq|ngword: "$_"| )
#                    for sort { length $a <=> length $b } keys %{$handle->{ngword}};
#            }
#        }
#        default {
#            $self->send_cmd( $handle, $self->daemon, 'NOTICE', $target, $_) for @action_command_info;
#        }
#    }
}

1;

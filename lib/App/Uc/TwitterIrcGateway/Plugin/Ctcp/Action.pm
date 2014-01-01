package App::Uc::TwitterIrcGateway::Plugin::Ctcp::Action;
use 5.014;
use parent 'Uc::IrcGateway::Plugin::Ctcp::Action';
use Uc::IrcGateway::Common;

my %ACTION_COMMAND = (
    mention      => qr{^me(?:ntion)?$},
    reply        => qr{^re(?:ply)?$},
    favorite     => qr{^f(?:av(?:ou?rites?)?)?$},
    unfavorite   => qr{^unf(?:av(?:ou?rites?)?)?$},
    retweet      => qr{^r(?:etwee)?t$},
    quotetweet   => qr{^(?:q[wt]|quote(?:tweet)?)$},
    delete       => qr{^(?:o+p+s+!*|del(?:ete)?)$},
    list         => qr{^li(?:st)?$},
    information  => qr{^in(?:fo(?:rmation)?)?$},
    conversation => qr{^co(?:nversation)?$},
    ratelimit    => qr{^(?:rate(?:limit)?|limit)$},
    ngword       => qr{^ng(?:word)?$},
);

my @ACTION_COMMAND_INFO = (qq|action commands:|
,  qq|/me mention (or me): fetch mentions|
,  qq|/me reply (or re) <tid> <text>: reply to a <tid> tweet|
,  qq|/me favorite (or f, fav) +<tid>: add <tid> tweets to favorites|
,  qq|/me unfavorite (or unf, unfav) +<tid>: remove <tid> tweets from favorites|
,  qq|/me retweet (or rt) +<tid>: retweet <tid> tweets|
,  qq|/me quotetweet (or qt, qw) <tid> <text>: quotetweet a <tid> tweet, like "<text> QT \@tid_user: tid_tweet"|
,  qq|/me delete (or del, oops) *<tid>: delete your <tid> tweets. if unset <tid>, delete your last tweet|
,  qq|/me list (or li) <screen_name>: list <screen_name>'s recent 20 tweets|
,  qq|/me information (or in, info) +<tid>: show <tid> tweets information. e.g. retweet_count, has conversation, created_at|
,  qq|/me conversation (or co) <tid>: show <tid> tweets conversation|
,  qq|/me ratelimit (or rate, limit): show remaining api hit counts|
,  qq|/me ngword (or ng) <text>: set/delete a NG word. if unset <text>, show all NG words|
);

sub action_command      { \%ACTION_COMMAND;      }
sub action_command_info { \@ACTION_COMMAND_INFO; }

sub check_params {
    my ($plugin, $self, $handle, $msg, $count) = @_;
    return 0 unless $self->check_connection($handle);

    $count //= 1;

    if (scalar $msg->{params} < $count) {
        $msg->{response}{command} = $msg->{command};
        $self->send_reply( $handle, $msg, 'ERR_NEEDMOREPARAMS' );
        return 0;
    }

    return 1;
}

sub event :CtcpEvent('ACTION') {
    my $self = shift;
    $self->run_hook('ctcp.action.begin' => \@_);

        action($self, @_);

    $self->run_hook('ctcp.action.end' => \@_);
}

sub action {
    my $self = shift;
    my ($handle, $msg, $plugin) = @_;
    return unless $self->check_params(@_);

    $self->run_hook('ctcp.action.start' => \@_);

    my ($command, $params) = split(' ', $msg->{params}[0], 2);
    $command //= "";
    $params  //= "";

    my @params = $params ? split(' ', $params) : ();
    my $target = $msg->{target};
    @{$msg}{qw/command params/} = ($command, \@params);

    my $action_command = $plugin->action_command;
    if ($command =~ /$action_command->{mention}/) {
        $params[0] //= '';
        my %opt;
        $opt{target}   = $target;
        $opt{since_id} = $handle->get_state('last_mention_id') if not $params[0] =~ /^f(?:o(?:rce)?)?$/ && $handle->get_state('last_mention_id');
        $self->get_mentions($handle, %opt);
    }
    elsif ($command =~ /$action_command->{reply}/) {
        my $reply = sub {
            return unless $plugin->check_params($self, $handle, $msg, 1);

            my ($tid, $text) = split(' ', $params, 2); $text //= '';
            return unless $self->check_ngword($handle, $text);

            my $tweet_id = $handle->{tmap}->get($tid);
            my $tweet = $self->get_tweet($handle, $tweet_id);
            if (!$tweet) {
                $text = "reply error: no such tid";
                $self->send_cmd( $handle, $self->daemon, 'NOTICE', $target, "$text [$tid]" );
            }
            else {
                $text = sprintf '@%s %s', $tweet->{nick}, $text;
                $self->api($handle, 'statuses/update', params => {
                    status => $text, in_reply_to_status_id => $tweet->{id},
                }, cb => sub {
                    my ($header, $res, $reason) = @_;
                    if (!$res) { $self->send_cmd( $handle, $self->daemon, 'NOTICE', $target,  qq|reply error: "$text": $reason| ); }
                } );
            }
        };
        $reply->();
    }
    elsif ($command =~ /$action_command->{favorite}/) {
        my $favorite = sub {
            return unless $plugin->check_params($self, $handle, $msg, 1);

            for my $tid (@params) {
                $self->tid_event($handle, 'favorites/create', $tid, target => $target, cb => sub {
                    my ($header, $res, $reason) = @_;
                    $self->log($handle, remark2db => { tid => $tid, favorited => 1 } ) if $res;
                });
            }
        };
        $favorite->();
    }
    elsif ($command =~ /$action_command->{unfavorite}/) {
        my $unfavorite = sub {
            return unless $plugin->check_params($self, $handle, $msg, 1);

            for my $tid (@params) {
                $self->tid_event($handle, 'favorites/destroy', $tid, target => $target, cb => sub {
                    my ($header, $res, $reason) = @_;
                    $self->log($handle, remark2db => { tid => $tid, favorited => 0 } ) if $res;
                });
            }
        };
        $unfavorite->();
    }
    elsif ($command =~ /$action_command->{retweet}/) {
        my $retweet = sub {
            return unless $plugin->check_params($self, $handle, $msg, 1);

            for my $tid (@params) {
                $self->tid_event($handle, 'statuses/retweet/:id', $tid, target => $target, cb => sub {
                    my ($header, $res, $reason) = @_;
                    $self->log($handle, remark2db => { tid => $tid, retweeted => 1 } ) if $res;
                });
            }
        };
        $retweet->();
    }
    elsif (/$action_command->{quotetweet}/) {
        my $quotetweet = sub {
            return unless $plugin->check_params($self, $handle, $msg, 1);

            my ($tid, $comment) = split(' ', $params, 2);
            break unless $self->check_ngword($handle, $comment);

            my $tweet_id = $handle->{tmap}->get($tid);
            my $tweet = $self->get_tweet($handle, $tweet_id);
            my $text;
            if (!$tweet) {
                $text = "quotetweet error: no such tid";
                $self->send_cmd( $handle, $self->daemon, 'NOTICE', $target, "$text [$tid]" );
            }
            else {
                my $notice = $tweet->{text};

                $comment = $comment ? $comment.' ' : '';
                $text    = sprintf "%sQT @%s: %s", $comment, $tweet->{nick}, $notice;
                while (length $text > 140 && $notice =~ /....$/) {
                    $notice =~ s/....$/.../;
                    $text   = sprintf "%sQT @%s:%s", $comment, $tweet->{nick}, $notice;
                }

                $self->api($handle, 'statuses/update', params => {
                    status => $text, in_reply_to_status_id => $tweet->{id},
                }, cb => sub {
                    my ($header, $res, $reason) = @_;
                    if (!$res) { $self->send_cmd( $handle, $self->daemon, 'NOTICE', $target, qq|quotetweet error: "$text": $reason| ); }
                } );
            }
        };
        $quotetweet->();
    }
    elsif ($command =~ /$action_command->{delete}/) {
        my $delete = sub {
            my @tids = @params;
            if (not scalar @tids) {
                my $topic = $handle->get_channels($handle->options->{stream})->topic // '';
                if (my @match = $topic =~ /\[(.+)\]/g) { @tids = pop @match; }
            }

            return if not scalar @tids;
            for my $tid (@tids) {
                $self->tid_event($handle, 'statuses/destroy/:id', $tid, target => $target, cb => sub {
                    my ($header, $res, $reason) = @_;
                    $self->log($handle, remark2db => { tid => $tid, retweeted => 0 } ) if $res;
                });
            }
        };
        $delete->();
    }
    elsif ($command =~ /$action_command->{list}/) {
        my $list = sub {
            return unless $plugin->check_params($self, $handle, $msg, 1);

            $self->api($handle, 'statuses/user_timeline', params => { screen_name => $params[0] }, cb => sub {
                my ($header, $res, $reason) = @_;
                if ($res) {
                    my $tweets = $res;
                    for my $tweet (reverse @$tweets) {
                        $self->process_tweet($handle, tweet => $tweet, target => $target, notice => 1);
                    }
                }
                else { $self->send_cmd( $handle, $self->daemon, 'NOTICE', $target, qq|list action error: $reason| ); }
            });
        };
        $list->();
    }
    elsif ($command =~ /$action_command->{information}/) {
        my $information = sub {
            return unless $plugin->check_params($self, $handle, $msg, 1);

            for my $tid (@params) {
                my $text;
                my $tweet_id = $handle->{tmap}->get($tid);
                if (!$tweet_id) {
                    $text = "information error: no such tid";
                    $self->send_cmd( $handle, $self->daemon, 'NOTICE', $target, "$text [$tid]" );
                }
                else {
                    $self->api($handle, "statuses/show/$tweet_id", cb => sub {
                        my ($header, $res, $reason) = @_;
                        if ($res) {
                            my $tweet = $res;
                            $text  = "information: $tweet->{user}{screen_name}: retweet count $tweet->{retweet_count}: source $tweet->{source}";
                            $text .= ": conversation" if $tweet->{in_reply_to_status_id};
                            $self->send_cmd( $handle, $self->daemon, 'NOTICE', $target, "$text ($tweet->{created_at}) [$tid]" );
                        }
                        else { $self->send_cmd( $handle, $self->daemon, 'NOTICE', $target, qq|information action error: $reason| ); }
                    });
                }
            }
        };
        $information->();
    }
    elsif ($command =~ /$action_command->{conversation}/) {
        my $conversation = sub {
            return unless $plugin->check_params($self, $handle, $msg, 1);

            my $tid = $params[0];
            my $tweet_id = $handle->{tmap}->get($tid);
            my @statuses;
            my $limit = 10;
            my $cb; $cb = sub {
                my ($header, $res, $reason) = @_;
                my $conversation = 0;

                if ($res) {
                    $conversation = 1 if $res->{in_reply_to_status_id};
                    push @statuses, $res;
                }
                else {
                    $self->send_cmd( $handle, $self->daemon, 'NOTICE', $target, qq|conversation error: $reason| );
                }

                if (--$limit > 0 && $conversation) {
                    $self->api($handle, 'statuses/show/'.$res->{in_reply_to_status_id}, cb => $cb);
                }
                else {
                    $self->send_cmd( $handle, $self->daemon, 'NOTICE', $target,
                        "conversation: there are more conversation before" ) if $limit <= 0;
                    for my $status (reverse @statuses) {
                        $self->process_tweet($handle, tweet =>  $status, target => $target, notice => 1);
                    }
                }
            };

            if (!$tweet_id) {
                my $text;
                $text = "conversation error: no such tid";
                $self->send_cmd( $handle, $self->daemon, 'NOTICE', $target, "$text [$tid]" );
            }
            else {
                $self->api($handle, 'statuses/show/'.$tweet_id, cb => $cb);
            }
        };
        $conversation->();
    }
    elsif ($command =~ /$action_command->{ratelimit}/) {
        my $ratelimit = sub {
            $self->api($handle, 'account/rate_limit_status', cb => sub {
                my ($header, $res, $reason) = @_;
                my $text;
                if (!$res) {
                    $text = "ratelimit error: $reason";
                }
                else {
                    my $limit = $res;
                    $text  = "ratelimit: remaining hits $limit->{remaining_hits}/$limit->{hourly_limit}";
                    $text .= ": reset time $limit->{reset_time}" if $limit->{remaining_hits} <= 0;
                }
                $self->send_cmd( $handle, $self->daemon, 'NOTICE', $target, $text);
            });
        };
        $ratelimit->();
    }
    elsif ($command =~ /$action_command->{ngword}/) {
        my $ngword = sub {
            my $text = "ngword:";
            my $word = lc $params;
            my $ngword = $handle->get_state('ngword');
            $ngword = +{} if ref $ngword ne 'HASH';
            if ($params) {
                if (exists $ngword->{$word}) {
                    delete $ngword->{$word};
                    $text .= qq| -"$word"|;
                }
                else {
                    $ngword->{$word} = 1;
                    $text .= qq| +"$word"|;
                }
                $handle->set_state('ngword', $ngword);
                $self->send_cmd( $handle, $self->daemon, 'NOTICE', $target, $text );
            }
            else {
                $self->send_cmd( $handle, $self->daemon, 'NOTICE', $target, qq|ngword: "$_"| )
                    for sort { length $a <=> length $b } keys %$ngword;
            }
        };
        $ngword->();
    }
    else {
        $self->send_cmd( $handle, $self->daemon, 'NOTICE', $target, $_ ) for @{$plugin->action_command_info};
    }

    $self->run_hook('ctcp.action.finish' => \@_);
}

1;

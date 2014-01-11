package App::Uc::TwitterIrcGateway v1.1.4;

use 5.014;
use warnings;
use utf8;

use parent 'Uc::IrcGateway';
use Uc::IrcGateway::Common;
use Uc::IrcGateway::TypableMap;
__PACKAGE__->load_components(qw/CustomRegisterUser Tweet/);
__PACKAGE__->load_plugins(qw/DefaultSet Irc::Pin/);

use Uc::Model::Twitter;
use Net::Twitter::Lite::WithAPIv1_1;
use AnyEvent::Twitter;
use AnyEvent::Twitter::Stream;
use HTML::Entities qw(decode_entities);
use DateTime::Format::DateParse;
use Config::Pit qw(pit_get);
use Scalar::Util qw(refaddr blessed);
use Clone qw(clone);

my %api_method = (
    post => qr {
        ^statuses
            /(?:update(?:_with_media)?|destroy|retweet)
        |
        ^(?:
            direct_messages
          | friendships
          | favorites
          | lists
          | lists/members
          | lists/subscribers
          | saved_searchs
          | blocks
         )
            /(?:new|update|create(?:_all)?|destroy(?:_all)?)
        |
        ^account
            /(?:
                update(?:
                    _delivery_device
                  | _profile(?:
                        _background_image
                      | _colors
                      | _image
                    )?
                )?
              | settings
              | remove_profile_banner
              | update_profile_banner
             )
        |
        ^notifications
            /(?:follow|leave)
        |
        ^geo/place
        |
        ^users/report_spam
        |
        ^oauth
            /(?:access_token|request_token)
        |
        ^oauth2
            /(?:token|invaildate_token)
    }x,
);


# TwitterIrcGateway subroutines #

sub validate_text {
    my $text = shift // return '';

    replace_crlf(decode_entities($text));
}

sub validate_user {
    my $user = shift;
    my @target_val = qw/name url location description/;
    my @escape = map { 'original_'.$_ } @target_val;
    @{$user}{@escape} = @{$user}{@target_val};
    $user->{name}        = validate_text($user->{name});
    $user->{url}         = validate_text($user->{url});
    $user->{location}    = validate_text($user->{location});
    $user->{description} = validate_text($user->{description});
    $user->{url} = "https://twitter.com/$user->{screen_name}" if $user->{url} eq '';

    $user->{_validated} = 1;
}

sub validate_tweet {
    my $tweet = shift;
    @{$tweet}{qw/original_text original_source/} = @{$tweet}{qw/text source/};
    $tweet->{text}   = validate_text($tweet->{text});
    $tweet->{source} = validate_text($tweet->{source});
    if (exists $tweet->{retweeted_status}) {
        @{$tweet->{retweeted_status}}{qw/original_text original_source/} = @{$tweet->{retweeted_status}}{qw/text source/};
        $tweet->{retweeted_status}{text}   = validate_text($tweet->{retweeted_status}{text});
        $tweet->{retweeted_status}{source} = validate_text($tweet->{retweeted_status}{source});
    }

    validate_user($tweet->{user}) if $tweet->{user} and not $tweet->{user}{_validated};

    $tweet->{_validated} = 1;
}

sub new_user {
    my $user = shift;
    validate_user($user) if !$user->{_validated};

    Uc::IrcGateway::TempUser->new(
        registered => 1,
        nick => $user->{screen_name}, login => $user->{id}, realname => $user->{name},
        host => 'twitter.com', addr => '127.0.0.1', server => $user->{url},
        away_message => $user->{location}, userinfo => $user->{description},
    );
}

sub datetime2simple {
    my ($created_at, $time_zone) = @_;
    my %opt = ();
    $opt{time_zone} = $time_zone if $time_zone;

    my $dt_now        = DateTime->now(%opt);
    my $dt_created_at = DateTime::Format::DateParse->parse_datetime($created_at);
    $dt_created_at->set_time_zone( $time_zone ) if $time_zone;

    my $date_delta = $dt_now - $dt_created_at;
    my $time = '';
       $time = $dt_created_at->hms            if $date_delta->minutes;
       $time = $dt_created_at->ymd . " $time" if $dt_created_at->day != $dt_now->day;

    $time;
}

use namespace::clean;

use Class::Accessor::Lite (
    rw => [qw(
        stream_channel
        activity_channel
    )],
    ro => [qw(
        consumer_key
        consumer_secret
    )],
);

sub new {
    my $class = shift;
    my %args = @_ == 1 ? %{$_[0]} : @_;

    my $consumer_key    = delete $args{consumer_key};
    my $consumer_secret = delete $args{consumer_secret};

    my $tweet2db = delete $args{tweet2db} // 0;

    # 初期値上書き
    $args{port}        //= 16668;
    $args{gatewayname} //= '*utigd';

    # プラグイン設定
    if ($tweet2db) {
        __PACKAGE__->load_plugins({
            module => 'Log::Tweet2DB',
            config => +{
                connect_info => [
                    'dbi:mysql:twitter', undef, undef, +{
                    mysql_enable_utf8 => 1,
                    on_connect_do     => ['set names utf8mb4'],
                }],
            }
        });
    }

    my $self = $class->SUPER::new(\%args);

    # 初期値設定
    $self->{stream_channel}   //= '#twitter';
    $self->{activity_channel} //= '#activity';

    $self->{consumer_key}    = $consumer_key;
    $self->{consumer_secret} = $consumer_secret;

    $self;
}

sub register_user {
    my ($self, $handle, $user) = @_;

    $self->twitter_configure($handle);
    if ($self->twitter_agent($handle)) {
        $self->join_channels($handle);
        return 1;
    }
    else {
        return 0;
    }
}


# TwitterIrcGateway method #

sub api {
    my ($self, $handle, $api, %opt) = @_;
    my $nt = $self->twitter_agent($handle);
    my $cb = delete $opt{cb} || delete $opt{callback};
    my %request;

    return unless $nt && $cb;

    $request{$api =~ /^http/ ? 'url' : 'api'} = $api;
    $request{params} = delete $opt{params} if exists $opt{params};
    $request{method} = $opt{method}                ? delete $opt{method}
                     : $api =~ /$api_method{post}/ ? 'POST'
                                                   : 'GET';

    $nt->request( %request, $cb );
}

sub tid_event {
    my ($self, $handle, $api, $tid, %opt) = @_;

    my $text = '';
    my $target = delete $opt{target} || $handle->self->nick;
    my $tweet_id = $handle->{tmap}->get($tid);
    my $tweet = $self->get_tweet($handle, $tweet_id);
    my @event = split('/', $api);
    my $event = $event[1] =~ /(create)|(destroy)/ ? ($2 ? 'un' : '') . $event[0]
                                                  : $event[1];

    if (!$tweet) {
        $text = "$event error: no such tid";
        $self->send_cmd( $handle, $self->daemon, 'NOTICE', $target, "$text [$tid]" );
    }
    else {
        my $cb = $opt{overload} && exists $opt{cb}       ? delete $opt{cb}
               : $opt{overload} && exists $opt{callback} ? delete $opt{callback} : sub {
            my ($header, $res, $reason) = @_;
            if (!$res) { $text = "$event error: $reason"; }
            else {
                $event =~ s/[es]+$//;
                $text = validate_text("${event}ed: ".$tweet->{nick}.": ".$tweet->{text});
            }
            $self->send_cmd( $handle, $self->daemon, 'NOTICE', $target, "$text [$tid]" );

            my $sub = exists $opt{cb}       ? delete $opt{cb}
                    : exists $opt{callback} ? delete $opt{callback} : undef;
            $sub->(@_) if defined $sub;
        };
        my $params = delete $opt{params} || +{};

        my %params;
        if ($event[0] eq 'favorites') {
            $params{id} = $tweet_id;
        }
        elsif ($api =~ /:id/) {
            $api =~ s/:id/$tweet_id/g;
        }
        $self->api($handle, $api, cb => $cb, params => \%params);
    }
}

sub check_ngword {
    my ($self, $handle, $msgtext) = @_;
    $msgtext //= '';
    if ($msgtext =~ /^\s/) {
        $msgtext =~ s/^\s+/\001/; $msgtext .= "\001";
    }
    my ($plain_text, $ctcp) = decode_ctcp($msgtext);
    my $ngword = $handle->get_state('ngword');
    $self->log($handle, debug => 'state.ngword: '.to_json($ngword));
    if (ref $ngword eq 'HASH') {
        for my $word (keys %$ngword) {
            if ($plain_text =~ /$word/i) {
                my $text = qq|ngword: "$word" is a substring of "$plain_text"|;
                while (length $text.$CRLF > $MAXBYTE && $text =~ /...."$/) {
                    $text =~ s/...."$/..."/;
                }
                $self->send_msg( $handle, ERR_NOTEXTTOSEND, $text );
                return 0;
            }
        }
    }
    return 1;
}

sub process_tweet {
    my ($self, $handle, %opt) = @_;

    my $target    = delete $opt{target};
    my $tweet     = delete $opt{tweet};
    my $notice    = delete $opt{notice};
    my $skip_join = delete $opt{skip_join};
    my $user      = $tweet->{user};
    return unless $user;

    my $login = $user->{id};
    my $nick  = $user->{screen_name};
    return unless $nick and $tweet->{text};

    my $raw_tweet = clone $tweet;
    $self->set_tweet($handle, $raw_tweet);
    $self->log($handle, tweet2db => $raw_tweet );

    validate_tweet($tweet);

    my $text = (defined $tweet->{retweeted_status} and defined $tweet->{retweeted_status}{user})
        ? sprintf('%c RT @%s: %s', 0x267b, $tweet->{retweeted_status}{user}{screen_name}, $tweet->{retweeted_status}{text})
        : $tweet->{text};
    my $stream_channel_name   = $handle->options->{stream};
    my $activity_channel_name = $handle->options->{activity};
    my $target_channel_name   = $target ? $target : $stream_channel_name;
    return unless $self->check_channel($handle, $target_channel_name, joined => 1, silent => 1);

    my $tmap = $handle->{tmap};
    my $old_user   = $handle->get_users($login);
    my $tid_color  = $handle->options->{tid_color}  // '';
    my $time_color = $handle->options->{time_color} // '';
    my $target_joined   = $self->check_channel($handle, $target_channel_name,   joined => 1, silent => 1);
    my $stream_joined   = $self->check_channel($handle, $stream_channel_name,   joined => 1, silent => 1);
    my $activity_joined = $self->check_channel($handle, $activity_channel_name, joined => 1, silent => 1);
    my $target_channel   = $handle->get_channels($target_channel_name);
    my $stream_channel   = $handle->get_channels($stream_channel_name);
    my $activity_channel = $handle->get_channels($activity_channel_name);

    my $real = $user->{name};
    my $url  = $user->{url};
    my $loc  = $user->{location};
    my $desc = $user->{description};

    # get and update from TempUser to Uc::IrcGateway::User
    my %old_status;
    my %new_status = (
        nick => $nick, real => $real,
        url  => $url,  loc  => $loc,  desc => $desc,
    );
    if (!$old_user) {
        $user = $handle->set_user(new_user($user));
        if (!$skip_join) {
            $stream_channel->join_users($user);
            $self->send_cmd( $handle, $user, 'JOIN', $stream_channel_name ) if $stream_joined;
        }
    }
    else {
        $user = $handle->get_users($login);
        $old_status{nick} = $user->nick;
        $old_status{real} = $user->realname;
        $old_status{url}  = $user->server;
        $old_status{loc}  = $user->away_message;
        $old_status{desc} = $user->userinfo;

        if (not eq_hash(\%old_status, \%new_status)) {
            $user->nick($nick);
            $user->realname($real);
            $user->server($url);
            $user->away_message($loc);
            $user->userinfo($desc);
            $user->update;

#            $self->notice_profile_update($handle, $user, \%old_status, \%new_status);
        }
    }

    # join the target channel
    if (!$skip_join && !$target_channel->has_user($login)) {
        $target_channel->join_users($user);
        $self->send_cmd( $handle, $user, 'JOIN', $target_channel_name ) if !$target_joined;
    }

    # check time delay
    my $time = datetime2simple($tweet->{created_at}, $self->time_zone);
       $time = " ($time)" if $time;

    # action command 'list'
    if ($notice) {
        $self->send_cmd( $handle, $user, 'NOTICE', $target_channel_name, "$text [$tmap]$time" );
    }

    # mention
    elsif ($target_channel_name eq $activity_channel_name) {
        $tweet->{_is_mention} = 1;
        $self->send_cmd( $handle, $user, 'PRIVMSG', $target_channel_name,
            $text." ".decorate_text("[$tmap]", $tid_color).decorate_text($time, $time_color) );
    }

    # not stream
    elsif ($target_channel_name ne $stream_channel_name) {
        $self->send_cmd( $handle, $user, 'PRIVMSG', $target_channel_name,
            $text." ".decorate_text("[$tmap]", $tid_color).decorate_text($time, $time_color) );
    }

    # myself
    elsif ($nick eq $handle->self->nick) {
        $handle->self($user);
        $stream_channel->topic("$text [$tmap]");
        $stream_channel->update;
        $self->send_cmd( $handle, $user, 'TOPIC',  $stream_channel_name,   "$text [$tmap]$time" );
        $self->send_cmd( $handle, $user, 'NOTICE', $activity_channel_name, "$text [$tmap]$time" );
        my $lists_include_own = $handle->get_state('lists_include_own');
        if (ref $lists_include_own eq 'HASH') {
            for my $list (keys $lists_include_own) {
                $self->send_cmd( $handle, $user, 'NOTICE', $list, "$text [$tmap]$time" );
            }
        }
    }

    # stream
    else {
        my @include_users;
        my @include_channels;

        push @include_users, $tweet->{in_reply_to_user_id} if defined $tweet->{in_reply_to_user_id};
        push @include_users, map { $_->{id} } @{$tweet->{user_mentions}} if exists $tweet->{user_mentions};
        my @user_mentions = $text =~ /\@(\w+)/g;
        if (scalar @user_mentions) {
            for my $u ($handle->get_users_by_nicks(@user_mentions)) {
                push @include_users, $u->login if defined $u;
            }
        }
        my %uniq;
        @include_users = grep { defined && !$uniq{$_}++ } @include_users;

        my %joined;
        for my $chan ($handle->who_is_channels($handle->self->login)) {
            $joined{$chan} = 1;
            for my $u (@include_users) {
                my $is_mention_to_me = $u == $handle->self->login;
                my $is_activity      = $chan eq $activity_channel_name;
                my $in_channel       = $handle->get_channels($chan)->has_user($u);
                if ($is_mention_to_me) {
                    $tweet->{_is_mention} = 1;
                    if ($is_activity && !$skip_join && !$activity_channel->has_user($user)) {
                        $activity_channel->join_users($user);
                        $self->send_cmd( $handle, $user, 'JOIN', $activity_channel_name );
                    }
                }
                push @include_channels, $chan
                    if $is_mention_to_me && $is_activity || !$is_mention_to_me && !$is_activity && $in_channel;
            }
        }
        push @include_channels, grep { $_ ne $activity_channel_name } $handle->who_is_channels($login);

        %uniq = ();
        for my $chan (grep { defined && !$uniq{$_}++ && $joined{$_} } @include_channels) {
            $self->send_cmd( $handle, $user, 'PRIVMSG', $chan,
                $text." ".decorate_text("[$tmap]", $tid_color).decorate_text($time, $time_color) );
        }
    }

    $handle->set_state(last_mention_id => $tweet->{id}) if $tweet->{_is_mention};

    $user->update({ last_modified => time });
    push @{$handle->{timeline}}, $tweet->{id};
}

sub process_event {
    my ($self, $handle, %opt) = @_;

    my $event  = delete $opt{event};
    my $target = $event->{target};
    my $source = $event->{source};
    my $happen = $event->{event};
    my $tweet  = $event->{target_object} // {};
    my $time   = $event->{created_at};
    return unless $event and $happen;

    my $login = $source->{id};
    my $nick  = $source->{screen_name};
    return unless $login and $nick;

    # ログインユーザがターゲット
    if ($target->{id} == $handle->self->login) {
        if ($happen) {
#            when ('favorite')   { ... } # Tweet
#            when ('unfavorite') { ... } # Tweet
#            when ('follow')     { ... } # Null
#            when ('list_member_added')        { ... } # List
#            when ('list_member_removed')      { ... } # List
#            when ('list_member_subscribed')   { ... } # List
#            when ('list_member_unsubscribed') { ... } # List
            validate_user($source);
            my $user = $handle->get_users($login) // $handle->set_user(new_user($source));
            my (%old_status, %new_status);
            my @status_keys = qw/nick real url loc desc/;
            my @source_keys = qw/screen_name name url location description/;
            $old_status{nick} = $user->nick;
            $old_status{real} = $user->realname;
            $old_status{url}  = $user->server;
            $old_status{loc}  = $user->away_message;
            $old_status{desc} = $user->userinfo;
            @new_status{@status_keys} = @{$source}{@source_keys};

            if (not eq_hash(\%old_status, \%new_status)) {
                $user->nick($source->{screen_name});
                $user->realname($source->{name});
                $user->server($source->{url});
                $user->away_message($source->{location});
                $user->userinfo($source->{description});
                $user->update;

#                $self->notice_profile_update($handle, $user, \%old_status, \%new_status);
            }

            my $activity_channel_name = $handle->options->{activity};
            my $activity_channel = $handle->get_channels($activity_channel_name);
            if (!$activity_channel->has_user($user)) {
                $activity_channel->join_users($user);
                $self->send_cmd( $handle, $user, 'JOIN', $activity_channel_name );
            }

            my $text = '';
            if ($tweet->{text}) {
                my $time = datetime2simple($tweet->{created_at}, $self->time_zone);
                $text  = validate_text("$tweet->{text} / https://twitter.com/$target->{screen_name}/status/$tweet->{id}");
                $text .= " ($time)" if $time;
            }
            my $notice = "$happen ".$handle->self->nick.($text ? ": $text" : "");
            $self->send_cmd( $handle, $user, 'NOTICE', $activity_channel_name, $notice );
        }
    }

    # ログインユーザの発生させたイベント
    elsif ($source->{id} == $handle->self->login) {
#        given (lc $happen) {
#            when ('user_update') { ... } # Null
#            when ('block')       { ... } # Null
#            when ('unblock')     { ... } # Null
#            when ('favorite')    { ... } # Tweet
#            when ('unfavorite')  { ... } # Tweet
#            when ('follow')      { ... } # Null
#            when ('unfollow')    { ... } # Null
#            when ('list_created')   { ... } # List
#            when ('list_destroyed') { ... } # List
#            when ('list_updated')   { ... } # List
#            when ('list_member_added')        { ... } # List
#            when ('list_member_removed')      { ... } # List
#            when ('list_member_subscribed')   { ... } # List
#            when ('list_member_unsubscribed') { ... } # List
#        }
    }
}

sub notice_profile_update {
    my ($self, $handle, $user, $old, $new) = @_;
    my $activity_channel_name = $handle->options->{activity};
    my $activity_joined       = $self->check_channel($handle, $activity_channel_name, joined => 1, silent => 1);
    my %change_message        = (
        nick => 'account name', real => 'profile name',
        url  => 'website',      loc  => 'location',     desc => 'description',
    );
    if ($old->{nick} ne $new->{nick}) {
        for my $chan ($handle->who_is_channels($user->login)) {
            $handle->get_channels($chan)->join_users($user->login => $new->{nick});
        }
        $self->send_cmd( $handle, $user, 'NICK', $new->{nick} );

        my $mes = "changed $change_message{nick} '$old->{nick}' to '$new->{nick}'";
        $self->send_cmd( $handle, $user, 'NOTICE', $activity_channel_name, $mes ) if $activity_joined;
    }
    if ($activity_joined) {
        for (sort grep { $_ ne 'desc' } keys %$new) {
            if ($old->{$_} ne $new->{$_}) {
                my $mes = "changed $change_message{$_} '$old->{$_}' to '$new->{$_}'";
                $self->send_cmd( $handle, $user, 'NOTICE', $activity_channel_name, $mes ) if $activity_joined;
            }
        }
        $self->send_cmd( $handle, $user, 'NOTICE', $activity_channel_name, "changed $change_message{desc}" ) if $old->{desc} ne $new->{desc};
    }
}

sub get_mentions {
    my ($self, $handle, %opt, %params) = @_;
    my $activity_channel = $handle->options->{activity};
    my $target = exists $opt{target} ? delete $opt{target} : $activity_channel;

    $params{count}    = $handle->options->{mention_count};
    $params{max_id}   = delete $opt{max_id}   if exists $opt{max_id};
    $params{since_id} = delete $opt{since_id} if exists $opt{since_id};
    $self->api($handle, 'statuses/mentions_timeline', params => \%params, cb => sub {
        my ($header, $res, $reason) = @_;
        if ($res) {
            my $mentions = $res;

            if (scalar @$mentions) {
                for my $mention (reverse @$mentions) {
                    $self->process_tweet($handle, tweet => $mention, target => $activity_channel);
                }
            }
            else {
                $self->send_cmd( $handle, $self->daemon, 'NOTICE', $target, qq|mention: no new mentions yet| );
            }
        }
        else {
            $self->send_cmd( $handle, $self->daemon, 'NOTICE', $target, qq|mention fetching error: $reason| );
        }
    });
}

sub join_channels {
    my ($self, $handle, $retry) = @_;
    return unless $self->check_connection($handle);

    my $stream_channel   = $handle->options->{stream};
    my $activity_channel = $handle->options->{activity};

    $handle->set_channels($activity_channel) if not $handle->has_channel($activity_channel);

    my $channel = $handle->get_channels($activity_channel);
    $channel->topic('@mentions and more');
    $channel->update;

    $self->handle_irc_msg( $handle, "JOIN $stream_channel,$activity_channel" );

    $self->fetch_list($handle, $retry);
}

sub fetch_list {
    my ($self, $handle, $retry) = @_;
    return unless $self->check_connection($handle);
    $retry ||= 5 + 1;

    $self->api($handle, 'lists/list', cb => sub {
        my ($header, $res, $reason, $error_res) = @_;

        if (!$res) {
            for my $error (@{$error_res->{errors}}) {
                $self->send_msg( $handle, 'NOTICE', "$error->{code}: $error->{message}");

                # ビジー以外のエラーであれば終了
                return if $error->{code} != 130 and $error->{code} != 131;
            }
            if (--$retry) {
                # 通信のエラーであればリトライ
                my $time = 10;
                my $text = "list fetching error (you will retry after $time sec): $reason";
                $self->send_msg( $handle, 'NOTICE', $text);
                my $w; $w = AnyEvent->timer( after => $time, cb => sub {
                    $self->fetch_list($handle, $retry);
                    undef $w;
                } );
            }
            else {
                # リトライ終了
                my $text = "list member fetching error. stop.";
                $self->send_msg( $handle, 'NOTICE', $text);
            }
        }
        else {
            my $lists = $res;
            my @chans;
            for my $list (@$lists) {
                next if $list->{user}{id} ne $handle->self->login;

                my $text = validate_text($list->{description});
                my $chan = '#'.$list->{slug};
                push @chans, $chan;

                $handle->set_channels($chan) if not $handle->has_channel($chan);

                my $channel = $handle->get_channels($chan);
                $channel->topic($text);
                $channel->update;

                $self->fetch_list_member($handle, $list->{slug});
            }
            $self->handle_irc_msg($handle, "JOIN ".join ",", @chans);
        }
    });
}

sub fetch_list_member {
    my ($self, $handle, $list, $retry) = @_;
    return unless $self->check_connection($handle);
    $retry ||= 5 + 1;

    my @users;
    my $page = -1;
    my $cb; $cb = sub {
        my ($header, $res, $reason, $error_res) = @_;

        if (!$res) {
            for my $error (@{$error_res->{errors}}) {
                $self->send_cmd($handle, $self->daemon, 'NOTICE', '#'.$list, "$error->{code}: $error->{message}");

                # ビジー以外のエラーであれば終了
                return if $error->{code} != 130 and $error->{code} != 131;
            }
            if (--$retry) {
                # 通信のエラーであればリトライ
                my $time = 10;
                my $text = "list member fetching error (you will retry after $time sec): $reason";
                $self->send_cmd($handle, $self->daemon, 'NOTICE', '#'.$list, $text);
                my $w; $w = AnyEvent->timer( after => $time, cb => sub {
                    $self->api($handle, 'lists/members', params => {
                        slug => $list, owner_id => $handle->self->login, cursor => $page,
                    }, cb => $cb);
                    undef $w;
                } );
            }
            else {
                # リトライ終了
                my $text = "list member fetching error. stop.";
                $self->send_cmd($handle, $self->daemon, 'NOTICE', '#'.$list, $text);
            }
        }
        else {
            push @users, @{$res->{users}};
            $page = $res->{next_cursor};

            if ($page) {
                # 次のページヘ
                $self->api($handle, 'lists/members', params => {
                    slug => $list, owner_id => $handle->self->login, cursor => $page,
                }, cb => $cb);
            }
            else {
                # 全ページ取得後
                my $chan = '#'.$list;
                $handle->set_channels($chan) if not $handle->has_channel($chan);
                my $channel = $handle->get_channels($chan);

                my $include_own = 0;
                my %list_user;
                my %newbie;
                for my $u (@users) {
                    my $user;
                    if ($u->{id} eq $handle->self->login) {
                        # 自身
                        $user = $handle->self;
                        $include_own = 1;
                    }
                    elsif (not $handle->has_user($u->{id})) {
                        # 新規
                        $user = $handle->set_user(new_user($u)->user_prop);
                    }
                    else {
                        # DBから取得
                        $user = $handle->get_users($u->{id});
                        $user->update(new_user($u)->user_prop);
                    }

                    # チャンネルにJOINしているかチェック
                    if (not $channel->has_user($user)) {
                        $channel->join_users($user);
                        $newbie{$user->login} = 1;
                    }
                    $list_user{$user->login} = 1;
                }

                # 自身を含むリスト情報の更新
                my $lists_include_own = $handle->get_state('lists_include_own');
                $lists_include_own = +{} if not ref $lists_include_own eq 'HASH';
                $self->log($handle, debug => "state.lists_include_own: ".to_json($lists_include_own));

                if ($include_own) {
                    $lists_include_own->{$chan} = 1;
                }
                else {
                    delete $lists_include_own->{$chan};
                }
                $handle->set_state('lists_include_own', $lists_include_own);

                my @list_users = $channel->users;
                my @join_users = grep { $newbie{$_->login} } @list_users;
                my @part_users = grep { $_->login ne $handle->self->login && not $list_user{$_->login} } @list_users;

                # リストに居ないユーザは退室
                $channel->part_users(@part_users);

                # JOIN and PART
                $self->send_cmd($handle, $_, 'PART', $chan, 'not list member') for @part_users;
                $self->send_cmd($handle, $_, 'JOIN', $chan) for @join_users;
            }
        }
    };

    $self->api($handle, 'lists/members', params => {
        slug => $list, owner_id => $handle->self->login, cursor => $page,
    }, cb => $cb);
}

sub twitter_configure {
    my ($self, $handle) = @_;

    my %opt = opt_parser($handle->self->realname);
    $handle->{options} = \%opt;
    $handle->options->{account} //= $handle->self->login;
    $handle->options->{mention_count} //= 20;
    $handle->options->{shuffle_tid} //= 0;
    $handle->options->{in_memory} //= 0;
    if (!$handle->options->{stream} ||
        not $self->check_channel($handle, $handle->options->{stream})) {
            $handle->options->{stream} = $self->stream_channel;
    }
    if (!$handle->options->{activity} ||
        not $self->check_channel($handle, $handle->options->{activity})) {
            $handle->options->{activity} = $self->activity_channel;
    }

    my ($consumer_key, $consumer_secret) = ($self->consumer_key, $self->consumer_secret);
    if ($handle->options->{consumer}) {
        ($consumer_key, $consumer_secret) = split /:/, $handle->options->{consumer};
    }
    $handle->{conf_app} = +{
        consumer_key    => $consumer_key,
        consumer_secret => $consumer_secret,
    };

    my $conf = $self->servername.'.'.$handle->options->{account};
    $handle->{conf_user} = pit_get( $conf );
    $handle->{timeline} = [];
    $handle->{tmap} = tie @{$handle->{timeline}}, 'Uc::IrcGateway::TypableMap', shuffled => $handle->options->{shuffle_tid};
}

sub twitter_agent {
    my ($self, $handle, $pin) = @_;
    return $handle->{nt} if ref $handle->{nt} eq 'AnyEvent::Twitter' && $handle->{nt}{authorized};

    my ($conf_app, $conf_user) = @{$handle}{qw/conf_app conf_user/};
    unless (blessed $handle->{nt} and $handle->{nt}->isa('Net::Twitter::Lite')) {
        $handle->{nt} = Net::Twitter::Lite::WithAPIv1_1->new(%$conf_app, useragent_args => { timeout => 10 });
    }

    my $nt = $handle->{nt};
    $nt->access_token($conf_user->{token});
    $nt->access_token_secret($conf_user->{token_secret});

    if ($pin) {
        eval {
            $self->log($handle, debug => sprintf "pin: %s, request_token: %s, request_token_secret: %s",
                $pin, $nt->request_token, $nt->request_token_secret,
            );
            @{$conf_user}{qw/token token_secret user_id screen_name/} = $nt->request_access_token(verifier => $pin);
            $nt->{config_updated} = 1;
        };
        if ($@) {
            $self->send_msg( $handle, ERR_YOUREBANNEDCREEP, "twitter authorization error: $@" );
        }
    }
    if ($nt->{authorized} = !!eval { $nt->verify_credentials; }) {
        my ($authorized, $config_updated) = @{$nt}{qw/authorized config_updated/};
        $handle->{nt} = AnyEvent::Twitter->new(
            consumer_key    => $handle->{conf_app}{consumer_key},
            consumer_secret => $handle->{conf_app}{consumer_secret},
            token           => $handle->{conf_user}{token},
            token_secret    => $handle->{conf_user}{token_secret},
        );
        $handle->{nt}{authorized}     = $authorized;
        $handle->{nt}{config_updated} = $config_updated;

        my $user = $handle->self;
        $user->nick($conf_user->{screen_name});
        $user->login($conf_user->{user_id});
        $user->host('twitter.com');
        $user->register($handle);
        $self->log($handle, info => sprintf "handle{%s} is registered as '%s' (account: %s)",
            refaddr $handle,
            $handle->self->to_prefix,
            $handle->options->{account},
        );

        $self->send_welcome($handle);

        return $handle->{nt};
    }
    else {
        $nt->{rate_limit_status} = eval { $nt->rate_limit_status; };
        if ($nt->{rate_limit_status} && $nt->{rate_limit_status}{remaining_hits} <= 0) {
            $self->send_msg($handle, 'NOTICE', "the remaining api request count is $nt->{rate_limit_status}{remaining_hits}.");
            $self->send_msg($handle, 'NOTICE', "twitter api calls are permitted $nt->{rate_limit_status}{hourly_limit} requests per hour.");
            $self->send_msg($handle, 'NOTICE', "the rate limit reset time is $nt->{rate_limit_status}{reset_time}.");
        }
        else {
            my $authorization_url = eval { $nt->get_authorization_url; };
            if (not $authorization_url) {
                $self->send_msg($handle, 'NOTICE', 'failed to get authorization url. shutdown connection.');
                $self->handle_irc_msg($handle, 'QUIT');
            } else {
                $self->send_msg($handle, 'NOTICE', 'please open the following url and allow this app, then enter /PIN {code}.');
                $self->send_msg($handle, 'NOTICE', $authorization_url);
            }
        }
    }

    return ();
}

sub streamer {
    my ($self, %config) = @_;
    my $handle = delete $config{handle};
    return $handle->{streamer} if defined $handle->{streamer};

    $handle->{streamer} = AnyEvent::Twitter::Stream->new(
        method  => 'userstream',
        timeout => 45,
        %config,

        on_connect => sub {
            $self->send_cmd( $handle, $self->daemon, 'NOTICE', $handle->options->{stream}, 'streamer start to read.' );
        },
        on_eof => sub {
            $self->send_cmd( $handle, $self->daemon, 'NOTICE', $handle->options->{stream}, 'streamer stop to read.' );
            delete $handle->{streamer};
            $self->streamer(handle => $handle, %config);
        },
        on_error => sub {
            $self->log($handle, error => $_[0]);
            return unless defined $handle;
            $self->send_cmd( $handle, $self->daemon, 'NOTICE', $handle->options->{stream}, "error: $_[0]" );
            delete $handle->{streamer};
            $self->streamer(handle => $handle, %config);
        },
        on_event => sub {
            my $event = shift;
            $self->process_event($handle, event => $event);
        },
        on_tweet => sub {
            my $tweet = shift;
            $self->process_tweet($handle, tweet => $tweet);
        },
    );
}


1;
__END__

=encoding utf-8

=head1 NAME

App::Uc::TwitterIrcGateway - Twitter IRC Gateway of me by me for me

=head1 SYNOPSIS

=head2 Configure consumer key that utig.pl uses

  $ script/utig.pl configure

  input Twitter consumer key:
  input Twitter consumer secret:

=head2 Start twitter irc gateway server

  $ script/utig.pl run --host 127.0.0.1 --port 16668

=head2 Login utig.pl server

=over 2

=item *

IRCクライアントで起動したサーバに適当な名前でログインする

=item *

暫くするとサーバーから OAuth 認証用の URL を渡されるので、それを開いて認証する

=item *

IRCクライアントで

  /pin <pin code>

=item *

そのうちTwitterストリームの読み込みが始まる

=back

=head1 DESCRIPTION

utig.pl は userstream の監視プログラムに毛が生えた程度のTwitter IRCゲートウェイサーバです

=head1 INSTALLATION

=head2 GitHub Checkout

  $ git clone git@github.com:UCormorant/utig.pl.git
  $ cd utig.pl/
  $ git submodule update --init
  $ cpanm --installdeps .

  # and run utig.pl

  $ perl script/utig.pl run

=head2 CPAN Minus

B<*it doesn't work yet!*>

  $ cpanm git@github.com:UCormorant/utig.pl.git

  # and run utig.pl
  $ utig run

=head1 FEATURES

=over 2

=item *

UserStream を使用して閲覧するので発言が即座に流れてくるぞ！

=item *

あんまり API を叩かない仕様だから他の Twitter 関連サービスと併用しても安心！

=item *

コマンドと自前で作った TypableMap が快適な Twitter Life をサポートするぞ！

=item *

Lists 対応。ただしリストに入れていてもフォローしてない人の発言は流れてこないぞ！
しかも自分が作ったリストしか見れないぞ！

=item *

MySQLにログたくさんとるぞ！(いまうごいてないです)

=item *

Follow, unfollow, direct message, block, list, account の操作？そんなもんねぇ！
(いつか対応予定です)

=item *

設定は C<$HOME/.utig> にみんな入ってる

=back

=head2 ACTION COMMANDS

CTCP-actionにいろんなコマンドを実装してあります。

  /me *command* *args*

上記のような感じで使います。

  /me mention (or me): fetch mentions.
  /me reply (or re) <tid> <text>: reply to a <tid> tweet.
  /me favorite (or f, fav) +<tid>: add <tid> tweets to favorites.
  /me unfavorite (or unf, unfav) +<tid>: remove <tid> tweets from favorites.
  /me retweet (or rt) +<tid>: retweet <tid> tweets.
  /me quotetweet (or qt, qw) <tid> <text>: quotetweet a <tid> tweet, like "<text> QT \@tid_user: tid_tweet".
  /me delete (or del, oops) *<tid>: delete your <tid> tweets. if unset <tid>, delete your last tweet.
  /me list (or li) <screen_name>: list <screen_name>'s recent 20 tweets.
  /me information (or in, info) +<tid>: show <tid> tweets information. e.g. retweet_count, has conversation, created_at.
  /me conversation (or co) <tid>: show <tid> tweets conversation.
  /me ratelimit (or rate, limit): show remaining api hit counts.

だいたいこんな感じ！

  [SPACE] f <tid>...

みたいに、先頭に空白入れると action として認識するのでいちいち C</me > とか打たなくてもへいきです

=head1 DEPENDENCIES

=head2 App::Uc::TwitterIrcGateway

=over 2

=item L<perl> >= 5.14

=item Uc::IrcGateway L<https://github.com/UCormorant/p5-uc-ircgateway>

=item Uc::Model::Twitter L<https://github.com/UCormorant/p5-uc-model-twitter>

=item L<Net::Twitter::Lite>

=item L<AnyEvent::Twitter>

=item L<AnyEvent::Twitter::Stream>

=item L<Clone>

=item L<Config::Pit>

=item L<DateTime::Format::DateParse>

=item L<HTML::Entities>

=item L<namespace::clean>

=back

=head2 utig.pl

=over 2

=item L<Data::Lock>

=item L<Smart::Options>

=item L<Term::ReadKey>

=back

=head1 BUGS AND LIMITATIONS

Please report any bugs or feature requests to
L<https://github.com/UCormorant/p5-app-uc-twitterircgateway/issues>

=head1 AUTHOR

L<https://twitter.com/c18t>

=head1 LICENCE AND COPYRIGHT

Copyright (C) U=Cormorant.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself. See L<perlartistic>.

=cut

import graphite.twitter;
import std.stdio;
import std.process;
import std.string;


void main()
{
    write("consumer-key: ");
    immutable consKey = readln().chomp();

    write("consumer-secret: ");
    immutable consSec = readln().chomp();

    auto reqTok = Twitter(Twitter.oauth.requestToken(ConsumerToken(consKey, consSec), null));
    browse(reqTok.callAPI!"oauth.authorizeURL"());

    write("pin: ");
    auto accTok = reqTok.callAPI!"oauth.accessToken"(readln().chomp());

    writefln("access-key: %s\naccess-sec: %s", accTok.key, accTok.secret);
}

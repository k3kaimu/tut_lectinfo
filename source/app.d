// Written in the D programming language.
/*
NYSL Version 0.9982

A. This software is "Everyone'sWare". It means:
  Anybody who has this software can use it as if he/she is
  the author.

  A-1. Freeware. No fee is required.
  A-2. You can freely redistribute this software.
  A-3. You can freely modify this software. And the source
      may be used in any software with no limitation.
  A-4. When you release a modified version to public, you
      must publish it with your name.

B. The author is not responsible for any kind of damages or loss
  while using or misusing this software, which is distributed
  "AS IS". No warranty of any kind is expressed or implied.
  You use AT YOUR OWN RISK.

C. Copyrighted to Kazuki KOMATSU

D. Above three clauses are applied both to source and binary
  form of this software.
*/

import core.thread;
import std.algorithm;
import std.array;
import std.conv;
import std.datetime;
import std.experimental.logger;
import std.file;
import std.format;
import std.functional;
import std.net.curl;
import std.path;
import std.random;
import std.range;
import std.regex;
import std.stdio;
import std.string;
import std.typecons;


import carbon.templates;

import graphite.twitter;
//import graphite.utils.log;

import msgpack;

import twitter_token;

enum lastInfoFilePath = "last.dat";

enum lectureInfoWebURL = "http://bit.ly/TYB9hb";
enum imcWebURL = "http://www.imc.tut.ac.jp/";
enum tutWebURL = "http://www.tut.ac.jp/";

immutable SysTime appStartTime;

Logger log;

static this()
{
    appStartTime = Clock.currTime;
    log = new FileLogger(File("log_tutlectinfo.txt", "a"));
}


string getHTML(string url)
{
    return std.net.curl.get(url).idup;
}


struct SavedData
{
    CancelInfo[] cancel;
    ExtraInfo[] extra;
    DateTime time;
    TweetWriter twWriter;

    string webHTML;
    string imcHTML;
    string lecHTML;

    void saveToFile(string filename){
        this.time = cast(DateTime)appStartTime;
        auto packed = pack(this);
        std.file.write(filename, packed);
    }


    static SavedData loadFromFile(string filename)
    {
        return unpack!(SavedData)(cast(ubyte[])std.file.read(filename));
    }


    void initialize(Twitter tw) nothrow
    {
        cancel = null;
        extra = null;
        time = appStartTime.to!DateTime();
        twWriter = TweetWriter(tw, dur!"seconds"(10));
    }
}


struct TweetWriter
{
    this(Twitter token, Duration interval) nothrow
    {
        _tw = token;
        _interval = interval;
    }


    string[] availables() @property
    {
        return _queue;
    }


    void put(string msg)
    {
        _queue ~= msg;
    }


    void flush()
    {
        immutable N = _queue.length;
        size_t i;
        _queue.popFront();
        try{
            while(!_queue.empty){
                immutable str = format("[%s/%s] %s", i+1, N, _queue.front);

                log.info(str);
                auto dstr = str.to!dstring;
                if(dstr.length > 130){
                    dstring buffer;
                    foreach(e; dstr.split()){
                        if(buffer.length + e.length < 130)
                            buffer ~= e;
                        else{
                            _tw.callAPI!"statuses.update"(["status" : buffer.to!string]);
                            core.thread.Thread.sleep(_interval/2);
                            buffer = e;
                        }
                    }

                    _tw.callAPI!"statuses.update"(["status" : buffer.to!string]);
                }else{
                    _tw.callAPI!"statuses.update"(["status" : str]);
                }

                core.thread.Thread.sleep(_interval);

                ++i;
                _queue.popFront();
            }
        }
        catch(Exception ex){
            log.error(ex);
        }
    }


  private:
    string[] _queue;
    Twitter _tw;
    Duration _interval;
}


void main()
{
    auto twitter = Twitter(accessToken);

    log.info("## START : ", appStartTime);
    scope(exit)
        log.info("## END : ", Clock.currTime, "\n");

    auto botData = () {
        SavedData loaded;
        {
            try loaded = SavedData.loadFromFile(lastInfoFilePath);
            catch(Exception ex){
                loaded.initialize(twitter);
                log.error(ex);
            }
        }
        return loaded;
    }();

    scope(exit)
        botData.saveToFile(lastInfoFilePath);


    bool[string] state;
    void adaptUpdateWebHTML(string mem)(string key, string url, string msg)
    {
        state[key] = true;
        try updateWebHTML!mem(botData, url, msg);
        catch(Exception ex)
            state[key] = false;
    }

    adaptUpdateWebHTML!"lecHTML"("lec", lectureInfoWebURL, "休講・補講情報ウェブページに更新があります " ~ lectureInfoWebURL);
    //adaptUpdateWebHTML!"webHTML"("web", tutWebURL, "TUTウェブページに更新があります");
    //adaptUpdateWebHTML!"imcHTML"("imc", imcWebURL, "IMCウェブページに更新があります");

    updateLectureInfo(botData);


    immutable twHeader =
    (){
        if(botData.twWriter.availables.length)
            return format("%s件の未ツイート情報があります。", botData.twWriter.availables.length);
        else
            return "";
    }()
    ~ (){
        string[] slist;
        if(!state["lec"])
            slist ~= "休講・補講情報";
        //if(!state["web"])
        //    slist ~= "TUTウェブページ";
        //if(!state["imc"])
            //slist ~= "IMCウェブページ";

        if(!slist.empty){
            return (botData.twWriter.availables.length ? "しかし残念ですが、" : "")
                    ~ slist.join("， ") ~ "の情報更新に失敗しました" ~ badEmojiList.randomSample(1).front;
        }else if(botData.twWriter.availables.length)
            return "今日も休講情報botは元気です" ~ goodEmojiList.randomSample(1).front;
        else
            return "";
    }();

    if(twHeader.length)
        twitter.callAPI!"statuses.update"(["status": twHeader]);

    {
        foreach(e; botData.cancel)
            if(botData.time.day < appStartTime.day && e.date == cast(Date)appStartTime
                && e.major.canFind(Major.elec) && e.grade.canFind(Grade.B4))
                with(e) botData.twWriter.put(mixin(Lstr!`@k3kaimu 今日の%[period%]限目の%[title%]は休講になりました`));

        foreach(e; botData.extra)
            if(botData.time.day < appStartTime.day && e.date == cast(Date)appStartTime
                && e.major.canFind(Major.elec) && e.grade.canFind(Grade.B4))
                with(e) botData.twWriter.put(mixin(Lstr!`@k3_kaimu 今日は%[period%]限目に%[title%]が入っています`));
    }


    botData.twWriter.flush();
}


//string testMsg()
//{
//    import std.random;
//    string[] msg = ["はいっ、休講botは大丈夫です！！",
//                    "休講botよ。一人前のbotとして扱ってよね！",
//                    "休講botなのです！",
//                    "もっと休講botに頼ってもいいのよ？"];

//    return msg[uniform(0, $)] ~ "（テストなう） on " ~ appStartTime.to!string();
//}


void updateWebHTML(string mem)(ref SavedData botData, string url, string msg)
if(is(typeof(mixin("botData." ~ mem)) : string))
{
    immutable string newHTML = getHTML(url);
    immutable string lastHTML = mixin("botData." ~ mem);

    scope(exit)
        mixin("botData." ~ mem) = newHTML;

    if(newHTML != lastHTML)
        botData.twWriter.put(msg);
}


void updateLectureInfo(ref SavedData botData)
{
    CancelInfo[] newCancelInfo = CancelInfo.parseHTML(botData.lecHTML);
    ExtraInfo[] newExtraInfo = ExtraInfo.parseHTML(botData.lecHTML);


    void findNewOrToday(T, U)(T[] newArray, U[] lastArray,
                   void delegate(T) onNew,
                   void delegate(T) onToday)
    if(is(Unqual!T : Unqual!U))
    {
        //writeln(newArray);
        foreach(i, e; newArray){
            // その日はじめて起動され、今日の情報なら
            if(botData.time.day < appStartTime.day && e.date == cast(Date)appStartTime)
                onToday(e);
            else if(lastArray.find(e).empty)
                onNew(e);
        }
    }


    string hashTags(T)(T e)
    {
        auto app = appender!string();
        foreach(g; e.grade){
            if(e.major.length >= 4)
                app.formattedWrite("#TUT%s_0 ", g);
            else{
                foreach(m; e.major)
                    app.formattedWrite("#TUT%s_%s ", g, cast(uint)m);
            }
        }

        return app.data;
    }


    findNewOrToday(newCancelInfo, botData.cancel,
        (CancelInfo e){
            immutable twText = "[%-(%s, %)] 系 [%-(%s, %)] %s の %s年%s月%s日%s限目の講義が休講になりました. %s"
                .format(e.major.map!(majorToString), e.grade, e.title, e.date.year, e.date.month.to!uint, e.date.day, e.period, hashTags(e));

            botData.twWriter.put(twText);
        },
        (CancelInfo e){
            immutable twText = "本日(%s年%s月%s日)%s限目 の [%-(%s, %)] 系 [%-(%s, %)] の %s の講義は休講です. %s"
                .format(e.date.year, e.date.month.to!uint, e.date.day, e.period, e.major.map!(majorToString), e.grade, e.title, hashTags(e));

            botData.twWriter.put(twText);
        }
    );
    botData.cancel = newCancelInfo;


    findNewOrToday(newExtraInfo, botData.extra,
        (ExtraInfo e){
            immutable twText = "[%-(%s, %)] 系 [%-(%s, %)] %s の補講が %s年%s月%s日%s限目に入りました. %s"
                .format(e.major.map!(majorToString), e.grade, e.title, e.date.year, e.date.month.to!uint, e.date.day, e.period, hashTags(e));

             botData.twWriter.put(twText);
        },
        (ExtraInfo e){
            immutable twText = "本日[%s年%s月%s日]、 [%-(%s, %)] 系 [%-(%s, %)] %s の講義が%s限目に入っています. %s"
                .format(e.date.year, e.date.month.to!uint, e.date.day,  e.major.map!(majorToString), e.grade, e.title, e.period, hashTags(e));

             botData.twWriter.put(twText);
        }
    );
    botData.extra = newExtraInfo;
}



enum Major
{
    comm,
    mach,
    elec,
    info,
    envi,
    soci,
}


string majorToString(Major mjr)
{
    final switch(mjr)
    {
        case Major.comm : return "共通";
        case Major.mach : return "1";
        case Major.elec : return "2";
        case Major.info : return "3";
        case Major.envi : return "4";
        case Major.soci : return "5";
    }
    assert(0);
}


enum Grade
{
    B1,
    B2,
    B3,
    B4,
    M1,
    M2,
    D1,
    D2,
    D3
}


struct ClassInfo
{
    Date date;
    uint[] period;
    string title;
    string teacher;
    Grade[] grade;
    Major[] major;


    static ClassInfo makeFromHTMLTable(R)(R r)
    if(isRandomAccessRange!R && is(ElementType!R : string))
    {
        ClassInfo info;
        info.date = Date(r[0].to!uint, r[1].to!uint, r[2].to!uint);
        //info.perod = r[4]..to!uint;

        foreach(cs; matchAll(r[4], ctRegex!`\d`))
            info.period ~= cs[0].to!uint;

        info.title = r[5];
        info.teacher = r[6];

        foreach(e; [__traits(allMembers, Grade)])
            if(!r[7].find(e).empty)
                info.grade ~= to!Grade(e);

        auto mjs = ["共" : Major.comm,
                    "機" : Major.mach,
                    "電" : Major.elec,
                    "知" : Major.info,
                    "環" : Major.envi,
                    "建" : Major.soci];

        foreach(k, v; mjs)
            if(!r[8].find(k).empty)
                info.major ~= v;

        return info;
    }
}


struct CancelInfo
{
    ClassInfo info;
    alias info this;


    enum header = `<th class="Head" scope="col">&nbsp;</th><th class="Head" scope="col">休講日</th><th class="Head" scope="col">時限</th><th class="Head" scope="col">時間割名</th><th class="Head" scope="col">担当教員</th><th class="Head" scope="col">開講年次</th><th class="Head" scope="col">開講学科</th><th class="Head" scope="col">学生への連絡</th><th class="Head" scope="col">補講の予定</th>`;
    enum dataHeader = `</td><td class="Row" width="10%">`;

    private{
        enum regexCancelDate = `(\d{4})/(\d{2})/(\d{2})\((.*)\)`;
        enum regexPeriod = `([^<>]+)`;
        enum regexClass = `([^<>]+)`;
        enum regexTeacher = `([^<>]+)`;
        enum regexGrade = `([^<>]+)`;
        enum regexMajor = `([^<>]+)`;
    }

    enum regexAllTable = `</td><td class="Row" width="10%">`
        ~ regexCancelDate ~ `</td><td class="Row" width="4%">`
        ~ regexPeriod ~ `</td><td class="Row" width="22%">`
        ~ regexClass ~ `</td><td class="Row" width="12%">`
        ~ regexTeacher ~ `</td><td class="Row" width="6%">`
        ~ regexGrade ~ `</td><td class="Row" width="8%">`
        ~ regexMajor ~ `</td><td class="Row" width="18%">`;


    static CancelInfo[] parseHTML(string html)
    {
        CancelInfo[] dst;

        immutable extHTML = html.find(ExtraInfo.header);
        html.parseClassInfo!(typeof(this), (a => a.length > extHTML.length),
            (a){
                dst ~= CancelInfo(ClassInfo.makeFromHTMLTable(a.array));
            }
        )();

        return dst;
    }
}


struct ExtraInfo
{
    ClassInfo info;
    alias info this;

    enum header = `<th class="Head" scope="col">&nbsp;</th><th class="Head" scope="col">補講日</th><th class="Head" scope="col">時限</th><th class="Head" scope="col">時間割名</th><th class="Head" scope="col">担当教員</th><th class="Head" scope="col">開講年次</th><th class="Head" scope="col">開講学科</th><th class="Head" scope="col">教室</th><th class="Head" scope="col">備考</th>`;
    enum dataHeader = `</td><td class="Row" width="10%">`;

    private{
        enum regexDate = `(\d{4})/(\d{2})/(\d{2})\((.*)\)`;
        enum regexPeriod = `([^<>]+)`;
        enum regexClass = `([^<>]+)`;
        enum regexTeacher = `([^<>]+)`;
        enum regexGrade = `([^<>]+)`;
        enum regexMajor = `([^<>]+)`;
    }

    enum regexAllTable = `</td><td class="Row" width="10%">`
        ~ regexDate ~ `</td><td class="Row" width="4%">`
        ~ regexPeriod ~ `</td><td class="Row" width="22%">`
        ~ regexClass ~ `</td><td class="Row" width="12%">`
        ~ regexTeacher ~ `</td><td class="Row" width="6%">`
        ~ regexGrade ~ `</td><td class="Row" width="18%">`
        ~ regexMajor ~ `</td><td class="Row" width="8%">`;


    static ExtraInfo[] parseHTML(string html)
    {
        ExtraInfo[] dst;

        html.parseClassInfo!(typeof(this), (a => a.length != 0),
            (a){
                dst ~= ExtraInfo(ClassInfo.makeFromHTMLTable(a.array));
            }
        )();

        return dst;
    }
}


void parseClassInfo(T, alias pred, alias callback)(string html)
{
    html = html.find(T.header)
          .drop(T.header.length)
          .find(T.dataHeader);

    while(unaryFun!pred(html))
    {
        scope(exit)
            html = html.find(T.dataHeader).drop(1).find(T.dataHeader);

        enum re = ctRegex!(T.regexAllTable);

        if(auto cp = html.matchFirst(re))
            unaryFun!callback(cp.drop(1));
    }
}


enum goodEmojiList = [
    `(・∀・)`,
    `(*´∀｀*)`,
    `(*‘ω‘ *)`,
    `ヽ(^o^)丿`,
    "ヽ(=´▽`=)ﾉ",
    `(b´∀｀)`,
    "( ^ω^ )ﾆｺﾆｺ",
    "(｢・ω・)｢ｶﾞｵｰ",
    "┌(_Д_┌ )┐",
];

enum badEmojiList = [
    "(´・ω・｀)",
    "(´・ω:;.:...",
    "(m´・ω・｀)m ｺﾞﾒﾝ…",
    "(ヽ´ω`)ﾊｧ…",
    "(´ﾍ｀；)ｳｰﾑ…",
    "ヽ(`Д´)ﾉｳﾜｧｧｧﾝ!!",
    "(_Д_)ｱｳｱｳｱｰ",
];

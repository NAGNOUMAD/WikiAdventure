package lobby;

import js.node.util.TextEncoder;
import js.Syntax;
import js.Browser;
import js.node.StringDecoder;
import haxe.Timer;
import js.Node;
import js.node.Buffer;
import haxe.Json;
import js.lib.Promise;
import js.node.Https.HttpsRequestOptions;
import js.node.Https;
import async.IO;
import js.node.socketio.Server.Namespace;
import js.node.socketio.Socket;
import haxe.io.Bytes;
import lobby.player.Player;
import config.Language;
import haxe.crypto.Base64;

class Lobby {
    
    public var io:Namespace;
    public var type:LobbyType;
    public var state:LobbyState;
    public var timeStampStateBegin:Float;
    public var loop:Timer;
    public var totalPlayer:Int = 0;

    public var startPage:String;
    public var endPage:String;

    public var slot:Int;
    public var id:Int;
    public var passwordHash:String;
    public var language:Language;
    public var playerList:Array<Player>;
    public var round:Int;
    public var currentRound:Int;
    public var playTimeOut:Int; //time in second before a round end automatically
    public var voteTimeOut:Int; //time of the Voting state
    public var roundFinishTimeOut:Int = 10; //time between the end of the play state and the begin of the vote state
    public var gameFinishTimeOut:Int = 30;

    public static var lobbyLimit:Int = 10000;
    public static var privateLimit:Int = 200;
    public static var lobbyList:Array<Lobby>;

    /**
     * instanciate the lobby list
     */
    public static function init() {
        lobbyList = new Array<Lobby>();
    }

    public function new(language : Language, type:LobbyType, ?passwordHash:String, slot:Int=15, round:Int=10, playTimeOut:Int=600, voteTimeOut:Int=30) {
        if (lobbyList.length >= lobbyLimit) {
            throw "Lobby limit has been reached!";
        } else if (getPrivateLobbyLength() >= privateLimit) {
            throw "Private lobby limit has been reached!";
        }
        playerList = new Array<Player>();
        this.language = language;
        this.type = type;
        this.slot = slot;
        this.round = round;
        currentRound = 1;
        this.playTimeOut = playTimeOut;
        this.voteTimeOut = voteTimeOut;
        this.passwordHash = passwordHash;
        
    }
    /**
     * give the lobby a valid id, loop until it found a unused one
     */
    public function giveID() {
        var pos = -1;
        do {
            id = Std.random(1048576);
            pos = checkIdUsed(id);
        } while (pos == -1);

        lobbyList.insert(pos,this);
        log("create the lobby", Info);
    }

    /**
     * Check if the randomly generated id is used
     * @param id futur id of the lobby
     * @return Int the position in the list of the futur lobby, return -1 if the id is already taken
     */
    //tested perform quite well can insert correctly 1000 lobby when there already 9000 lobby in 0.000013 ~ 0.000014
    public static function checkIdUsed(id:Int):Int {
        var i=0;
        for (l in lobbyList) {
            if (l.id > id) return i; // because the list is sorted, so if the id is inferior to the next one it means the id is between the last and the next one
            if (l.id == id) return -1;
            i++;
        }
        return i;
    }

    public static function find(id:Int):Lobby {
        for (l in lobbyList) {
            if (l.id > id) throw "no lobby with id " + id + " found";
            if (l.id == id) return l;
        }
        throw "no lobby with id " + id + " found";
    }


    /**
     * add player to the lobby ( and check if is not already in )
     * @param player to add
     */
    public function addPlayer(player:Player) {
        if (playerList.length >= slot) throw "the lobby is full";
        if (playerList.lastIndexOf(player) == -1) {
            playerList.push(player);
            log("new player registered : " + player.uuid + " --> " + player.pseudo, PlayerData);
            Timer.delay(function () {
                if (player.socket == null) {
                    removePlayer(player);
                }
            },30000);
        }
    }

    public function connect(player:Player, ?passwordHash:String) {
        if (this.type == Public || this.passwordHash == passwordHash) return addPlayer(player);
        log("connection rejected : " + player.uuid + " --> " + player.pseudo + "provide a wrong password", PlayerData);
        throw "Invalid password";
    }
    /**
     * remove a player from the lobby and remove the lobby if he go empty
     * @param player to remove
     */
    public function removePlayer(player:Player) {
        playerList.remove(player);
        log("player left : " + player.uuid + " --> " + player.pseudo, PlayerData);
        if (playerList.length == 0) {
            log("No player left, closing the lobby", Info);
            deleteLobby();
        }
    }

    public function deleteLobby() {
        log("delete the lobby", Info);
        Lobby.lobbyList.remove(this);
    }

    public function getPlayerFromSocket(socket:Socket):Player {
        for (p in playerList) {
            if (p.socket == socket) {
                return p;
            }
        }
        return null;
    }

    public function getPlayerFromUUID(uuid:String):Player {
        for (p in playerList) {
            if (p.uuid == uuid) {
                return p;
            }
        }
        return null;
    }

    /**
     * create a socket io namespace for the lobby and assign data handler to each channel
     */
    public function initNamespace() {
        log("init a socket io namespace for the lobby", Info);
        io = IO.server.of('/'+encodeID(id));//the name of the lobby is his id encoded in Base64
        /** 
        * middleware that accept connection only from client that provide a correct player uuid from playerList of the lobby
        * if the provided uuid is valid assign the socket to the player
        */
        io.use(function (socket, next) {
            var player = getPlayerFromUUID(untyped __js__("socket.handshake.query.playerID"));
            if ( player != null ) {
                if (player.assignSocket(socket) ) {
                    player.id = totalPlayer;
                    totalPlayer++;
                    return untyped __js__("next()");
                }
                return untyped __js__("next(new Error('Connection rejected because there already a client connected with this playerID'))");
            }
            return untyped __js__("next(new Error('Connection rejected because playerID is not registered in the lobby'))");
            
        });
        io.on('connection', function(socket:Socket, request) {
            var player = getPlayerFromSocket(socket);
            if (player == null) return;
            io.emit('message', player.pseudo + " join the lobby!");
            sendCurrentState(player);
            io.emit('newPlayer', player.id + ":" + player.pseudo + ":" + player.score);
            socket.on('message', function (data) {
                var player = getPlayerFromSocket(socket);
                if (player == null) return;
                io.emit('message', player.pseudo + " : " + data);
            });
            socket.on('disconnect', function (data) {
                var player = getPlayerFromSocket(socket);
                if (player == null) return;
                io.emit('playerLeft', player.id);
                io.emit('message', player.pseudo + " has left the lobby!");
                removePlayer(player);
            });
            socket.on('vote', function (data) {
                vote(socket, data);
            });
            socket.on('validateJump', function (data) {
                validateJump(socket, data);
            });
        });
    }

    public function sendCurrentState(player:Player) {
        var timeLeft = currentStateTimeOut() - (Timer.stamp() - timeStampStateBegin);
        player.socket.emit('gameState', state +"|" + currentRound + "|" + timeLeft);
        if (state == Playing) {
            player.currentPage = startPage;
            player.socket.emit('voteResult', startPage + '?' + endPage);
        }
        for (otherPlayer in playerList) {
            player.socket.emit('newPlayer', otherPlayer.id + ":" + otherPlayer.pseudo + ":" + otherPlayer.score);
        }
    }

    /**
     * get the current state duration
     * @return Int current state duration in seconde
     */
    public function currentStateTimeOut():Int {
        switch state {
            case Playing:
                return playTimeOut;
            case Voting:
                return voteTimeOut;
            case RoundFinish:
                return roundFinishTimeOut;
            case GameFinish:
                return gameFinishTimeOut;
        }
    }

    public function wikiTitleFormat(s:String):String {
        return s;
        
        var regex = ~/["%&'+=?\\^`~]/g; // anything like ${ ... }
            var format = regex.map(s, function(r) {
                var match = r.matched(0);
                switch (match) {
                    case "\"":
                        return "%22";
                    case "%":
                        return "%25";
                    case "&":
                        return "%26";
                    case "'":
                        return "%27";
                    case "+":
                        return "%2B";
                    case "=":
                        return "%3D";
                    case "?":
                        return "%3F";
                    case "\\":
                        return "%5C";
                    case "^":
                        return "%5E";
                    case "`":
                        return "%60";
                    case "~":
                        return "%7E";
                    case "_":
                        return " ";
                    default:
                        return '';
                }
            });
        return format;
    }

    /**
     * check if the player jump is valid (when he click on a link to go to an another page)
     * we ask the wikipedia api to do so
     * @param socket from which the data come from
     * @param url 
     */
    public function validateJump(socket:Socket, url:String) {
        trace(url);
        var player = getPlayerFromSocket(socket);
        if (player == null) return;
        if (wikiTitleFormat(player.currentPage) == wikiTitleFormat(url)) return;
        var requestPath = untyped __js__(" encodeURI('/w/api.php?action=query&utf8=1&prop=links&format=json&redirects=1&formatversion=2&titles=')") + wikiTitleFormat(untyped __js__("encodeURIComponent(decodeURIComponent(player.currentPage))")) + untyped __js__(" encodeURI('&pltitles=')") + wikiTitleFormat(untyped __js__("encodeURIComponent(decodeURIComponent(url))"));
        log(player.pseudo + " validation --> " + requestPath, PlayerData);
        var options:HttpsRequestOptions =  {
            hostname: LanguageTools.getURL(language),
            path: requestPath,
            method: 'POST',
            headers: {
                "Api-User-Agent":"pediaFinder/1.1 (https://pedia-finder.herokuapp.com/; benjamin.gilloury@gmail.com)",
                'Accept': 'application/json',
                'Content-type': "application/x-www-form-urlencoded"

            }
            
        };
        var request = Https.request(options, function (response) {
            var body = '';

            response.on('data', function (chunk) {
                body = body + chunk;
            });
            response.on('end', function () {
                try {
                    var parsed:WikiResponse = Json.parse(body);
                    if (parsed.query.pages[0].links == null) {
                        //kick for cheating
                        log(body, PlayerData);
                        log(player.pseudo + " is cheating!", PlayerData);
                        log(player.currentPage + " --> " + url, PlayerData);
                        io.emit('message', "it seems that " + player.pseudo + " is cheating! (or the anticheat system is broken)");
                        io.emit('message', player.pseudo + "jump from " + player.currentPage + " to " + StringTools.urlDecode(url));
                    } else {
                        player.numberOfJump +=1;
                        player.currentPage = url;
                        if (StringTools.urlDecode(url) == endPage) {
                            startPage = null;
                            endPage = null;
                            var timeLeft = currentStateTimeOut() - (Timer.stamp() - timeStampStateBegin);
                            player.score += 500 + Std.int(timeLeft);
                            log("updateScore --> " +  player.id + "(" + player.pseudo + ") :" + player.score, PlayerData);
                            log("WinRound --> " +  player.id + "(" + player.pseudo + ")", PlayerData);
                            io.emit('updateScore', player.id + ":" + player.score);
                            io.emit('winRound', player.pseudo);
                            io.emit('message', player.pseudo + " win the round " + currentRound);
                            currentRound++;
                            loop.stop();
                            votePhase();
                        }             
                    }
                } catch(e:Dynamic) {
                    //untyped __js__(" encodeURI(requestPath)")
                    log(requestPath, Error);
                    log("Wiki request error during the anti cheat validation : " + e + " | \n" + body, Error);
                }
            });
        });
        request.on('error', function (e) {
            log("Wiki request error during the anti cheat validation : " + e, Error);
        });
        request.end();
    }

    /**
     * find the player from his socket
     * and assign his vote to the [votingSuggestion] variable of the player
     * PS: we don't verify if the title lead to something, we will in the [selectPage()] method
     * the client also do the verification so they are aware if there title lead to something
     * @param socket from which the data come from
     * @param content the page title we receive
     */
    public function vote(socket:Socket, content:String) {
        var player = getPlayerFromSocket(socket);
        log("player vote : " + player.uuid + " --> " + player.pseudo + " | " + content, PlayerData);
        if (player != null) player.votingSuggestion = content;
    }

    /**
     * start the voting phase
     * and call selectPage when the timer run out
     */
    public function votePhase() {
        state = Voting;
        initNewPhase();
        if (loop != null) loop.stop();
        loop = Timer.delay(function () {
            selectPage();
        },currentStateTimeOut()*1000);
    }

    /**
     * randomly pick a start page and a end page from each player vote
     * if an player did not vote, we picked random page to replace his vote
     * if there is only 1 player we picked an another random page
     * start the play phase when the selection is completed
     * TODO : pick a random page if start and end page are the same
     * PS: NOT OPTIMISED but we do like that so in the future we can do a little drawing animation client side
     */
    public function selectPage() {
        var promiseList = new Array<Promise<Bool>>();
        var urlList = new Array<String>();
        log("Starting page selection", Info);
        for (i in 0...playerList.length) {
            var title = playerList[i].votingSuggestion;
            if (title != null) {
                title = StringTools.urlEncode(title);
                var promise = new Promise<Bool>(
                    function (resolve, reject) {
                        var options:HttpsRequestOptions =  {
                            hostname: LanguageTools.getURL(language),
                            path: "/w/api.php?action=query&list=search&srlimit=1&srnamespace=0&srsearch=intitle:" + title + "&format=json&srprop="
                        };
                        var request = Https.request(options, function (response) {
                            response.on('data', function (data) {
                                try {
                                    var parsed:WikiResponse = Json.parse(data);
                                    if (parsed.query.searchinfo.totalhits == 0) {
                                        getRandomURL(urlList, resolve, reject);
                                    } else {
                                        var spaceRegex = ~/ +/g;
                                        var url =  spaceRegex.replace(parsed.query.search[0].title, "_");
                                        urlList.push(url);
                                        resolve(true);
                                    }
                                } catch(e:Dynamic) {
                                    reject("SEVERE server Error : " + e);
                                }
                            });
                        });
                        request.on('error', function (e) {
                            log("page selection : " + e, Error);
                        });
                        request.end();
                    }
                );
                promiseList.push(promise);
            } else {
                var promise = new Promise<Bool>(
                    function (resolve, reject) {
                        getRandomURL(urlList, resolve, reject);
                    }
                );
                promiseList.push(promise);
            }
        }
        if (playerList.length < 2) {
            var promise = new Promise<Bool>(
                function (resolve, reject) {
                    getRandomURL(urlList, resolve, reject);
                }
            );
            promiseList.push(promise);
        }
        Promise.all(promiseList).then(
            function(value) {
                var randomStart = Std.random(urlList.length);
                var randomEnd:Int;
                do {
                    randomEnd = Std.random(urlList.length);
                } while (randomEnd == randomStart);
                startPage = urlList[randomStart];
                endPage = urlList[randomEnd];
                log("Start page : " + startPage, Info);
                log("End page : " + endPage, Info);
                playPhase();

            }, function(reason) {
                log("SEVERE something wrong append during page selection : " + reason, Error);
        });
    }

    /**
     * set the current page of each player to the starting one who get the picked in the voting phase
     * send the starting and ending page to the client
     * start the playing phase
     * and start the interlude phase when the timer run out
     */
    public function playPhase() {
        for (player in playerList) {
            player.currentPage = wikiTitleFormat(startPage);
        }
        io.emit('voteResult', startPage + '?' + endPage);
        state = Playing;
        initNewPhase();
        loop.stop();
        loop = Timer.delay(function () {
            playPhaseEnd();
        },currentStateTimeOut()*1000);
    }

    public function playPhaseEnd() {
        currentRound++;
        if (currentRound > round) {
            gameFinishPhase();
            return;
        }
        votePhase();
    }

    public function gameFinishPhase() {
        currentRound = 1;
        state = GameFinish;
        initNewPhase();
        loop.stop();
        loop = Timer.delay(function () {
            votePhase();
        },currentStateTimeOut()*1000);

    }

    /**
     * start the interlude phase between the voting and playing phase
     * and start the voting phase when the timer run out
     */
    public function roundFinishPhase() {
        state = RoundFinish;
        initNewPhase();
        loop.stop();
        loop = Timer.delay(function () {
            votePhase();
        },currentStateTimeOut()*1000);
    }
    /**
     * refresh the [timeStampBegin] variable
     * and send the state time avaible to the client
     */
    public function initNewPhase() {
        timeStampStateBegin = Timer.stamp();
        io.emit('gameState', state +"|" + currentRound + "|" + currentStateTimeOut());
        log("New phase init : " + state +"|" + currentRound + "|" + currentStateTimeOut(), Info);
    }

    /**
     * request the wikipedia api and get a random page
     * @param urlList the list on wich we will add the random url if nothing go wrong
     * @param resolve the promise resolve
     * @param reject the promise reject
     */
    public function getRandomURL(urlList:Array<String>, resolve:(value:Bool) -> Void, reject:(reason:Dynamic) -> Void) {
        var options:HttpsRequestOptions =  {
            hostname: LanguageTools.getURL(language),
            path: "/w/api.php?action=query&format=json&list=random&rnnamespace=0&rnlimit=1"
        }
        var request = Https.request(options, function (response) {
            response.on('data', function (data) {
                try {
                    var parsed:WikiResponse = Json.parse(data);
                    var spaceRegex = ~/ +/g;
                    var url =  spaceRegex.replace(parsed.query.random[0].title, "_");
                    urlList.push(url);
                    resolve(true);
                    log("success : random page " + url, Info);
    
                } catch(e:Dynamic) {
                    log("random page request fail : " + e, Error);
                    reject("SEVERE server Error : " + e);
                }   
            });
        });
        request.on('error', function (e) {
            log("Wiki request error : " + e, Error);
        });
        request.end();

    }

    /**
     * Search a Lobby of type public and add the player to this one, if no lobby is found, it create one.
     * @param player who want to join
     * @return the lobby
     */
     public static function joinPublicFree(player:Player):Lobby {
        for (l in lobbyList) {
            if (l.type == Public && (l.slot > l.playerList.length)) {
                if ( l.language == player.language ) {
                    l.connect(player);
                    return l;
                }
            }
        }
        // if no free slot are find create a new public lobby
        var lobby = new Lobby(player.language, Public);
        lobby.giveID();// giveID method also add the lobby to the lobbylist
        lobby.initNamespace();
        lobby.votePhase();
        lobby.connect(player);
        return lobby;
    }

    /**
     * get the number of private lobby in the lobby list
     * @return Int
     */
     public static function getPrivateLobbyLength():Int {
        var n = 0;
        for (l in lobbyList) {
            if (l.type == Private) n++;
        }
        return n;
    }

    /**
     * transform the url string into the lobby id
     * @param id in url string format
     * @return Int The lobby id
     */
     public static function decodeID(id:String):Int {
        var bytesValue = Base64.urlDecode(id);
        var stringValue = bytesValue.getString(0,bytesValue.length);
        var intValue = Std.parseInt(stringValue);
        if(intValue == null) {
            throw "invalid ID";
        }
        return intValue;
    }
    /**
     * tranform the lobby id into url string
     * @param id in Int format
     * @return the url String
     */
    public static function encodeID(id:Int):String {
        var bytesValue = Bytes.ofString(Std.string(id));
        var result = Base64.urlEncode(bytesValue);
        return result;
    }
    public function log( data : Dynamic, logType:LogType, ?pos : haxe.PosInfos ) {
        var time = "[" + Date.now().toString() + "]";
		pos.fileName = time + " lobby " + Lobby.encodeID(id) + " " + logType + " -> " + pos.fileName;
        haxe.Log.trace(data, pos);
        var fileName = "lobby/" + Lobby.encodeID(id) + "/" + logType + ".log";
        var content = haxe.Log.formatOutput(data, pos);
        fileLog.Log.inFile(fileName, content);
	}

}

enum abstract LogType(String) {
    var PlayerData;
    var Warning;
    var Error;
    var Info;
}

enum abstract LobbyType(Int) {
    var Public;
    var Private;
}

enum abstract LobbyState(String) from String to String {
    var Voting;
    var Playing;
    var RoundFinish;
    var GameFinish;
}

typedef WikiResponse = {
    var query:WikiQuery;
}
typedef WikiQuery = {
    var searchinfo:{
        var totalhits:Int;
    };
    var search:Array<WikiResult>;
    var random:Array<WikiResult>;
    var pages:Array<WikiResult>;
}
typedef WikiResult = {
    var ns:Int;
    var title:String;
    var pageid:Int;
    var links:Array<WikiResult>;
}

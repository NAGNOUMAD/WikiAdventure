import { Lang } from 'src/i18n';
import { ActionTree } from 'vuex';
import { StateInterface } from '../index';
import { GameData, LobbyType } from './state';
import { PhaseType } from './type/phase';

const actions: ActionTree<GameData, StateInterface> = {
  connect({ commit, dispatch, state }) {
    var loc = window.location;
    var protocol = loc.protocol == "https:" ? "wss://" : "ws://";
    var lobbyType = state.lobbyType == LobbyType.Twitch ? "twitchLobby" : "lobby";
    if(process.env.DEV) {
      var wsURL = protocol + "localhost:5000" + "/" + lobbyType + "/" + state.lobbyID + "/" + state.uuid;
    } else {
      var wsURL = protocol + loc.host + "/" + lobbyType + "/" + state.lobbyID + "/" + state.uuid;
    }
    state.ws  = new WebSocket(wsURL);
    function dataHandler(e:MessageEvent) {
      var json:LobbyEvent<any> = JSON.parse(e.data);
      switch (json.type) {
        case LobbyEventType.Message: {
          return dispatch('onMessage', json.data);
        };
        case LobbyEventType.GameState: {
          return dispatch('onGameState', json.data);
        };
        case LobbyEventType.VoteResult: {
          return dispatch('onVoteResult', json.data);
        };
        case LobbyEventType.UpdateScore: {
          return dispatch('onUpdateScore', json.data);
        };
        case LobbyEventType.WinRound: {
          return dispatch('onWinRound', json.data);
        };
        case LobbyEventType.PlayerJoin: {
          return dispatch('onPlayerJoin', json.data);
        };
        case LobbyEventType.PlayerLeft: {
          return dispatch('onPlayerLeft', json.data);
        };
        case LobbyEventType.SetOwner: {
          return dispatch('onSetOwner', json.data);
        };
        case LobbyEventType.Path: {
          return dispatch('onPath', json.data);
        };
        case LobbyEventType.VoteSkip: {
          return dispatch('onVoteSkip', json.data);
        };
        case LobbyEventType.VoteSkip: {
          return dispatch('onRollback', json.data);
        };
        default: {
          return;
        }
      }
    };
    function closeHandler(e:CloseEvent) {
      console.log(e.code, e.reason);
    };
    function errorHandler(e:Event) {
      console.log(e);
    };
    function onOpen(e:Event) {
      console.log(e);
    };
    state.ws.onmessage = dataHandler;
    state.ws.onclose = closeHandler;
    state.ws.onerror = errorHandler;
    state.ws.onopen = onOpen;
  },
  onMessage({ commit }, data:WsMessage) {
    commit('pushMessage', data);
  },
  onGameState({ commit }, data:GameState) {
    commit('gameState', data);
  },
  onVoteResult({ commit }, data:VoteResult) {
    commit('voteResult', data);
  },
  onUpdateScore({ commit }, data:UpdateScore) {
    commit('updateScore', data);
  },
  onWinRound({ commit }, data:WinRound) {
    commit('winRound', data);
  },
  onPlayerJoin({ commit }, data:PlayerJoin) {
    commit('playerJoin', data);
  },
  onPlayerLeft({ commit }, data:PlayerLeft) {
    commit('playerLeft', data);
  },
  onSetOwner({ commit }, data:SetOwner) {
    commit('setOwner', data.id);
  },
  onPath({ commit }, data:Path) {
    commit('path', data);
  },
  onVoteSkip({ commit }, data:VoteSkip) {
    commit('voteSkip', data);
  },
  onRollback({ commit }, data:Rollback) {
    commit('voteSkip', data);
  },
  sendStart({ state }) {
    var json:WebsocketPackage = {
      type: WebsocketPackageType.Start,
    };
    state.ws?.send(JSON.stringify(json));
  },
  sendMessage({ state }, data) {
    var json:WebsocketPackage = {
      type: WebsocketPackageType.Message,
      value: data
    };
    state.ws?.send(JSON.stringify(json));
  },
  searchVote({ state, dispatch }, vote) {
    fetch("https://" + state.lang + ".wikipedia.org/w/api.php?action=query&origin=*&list=search&srlimit=1&srnamespace=0&srsearch=intitle:" + encodeURIComponent(vote) + "&format=json&srprop=")
      .then(function(response){return response.json();})
      .then(function(response) {
        var trueTitle;
        if (typeof response.query.search[0] === 'undefined') trueTitle = "no page found";
        else trueTitle = response.query.search[0].title;
        state.vote = vote + " → " + trueTitle;
    });    fetch("https://" + state.lang + ".wikipedia.org/w/api.php?action=query&origin=*&list=search&srlimit=1&srnamespace=0&srsearch=intitle:" + encodeURIComponent(vote) + "&format=json&srprop=")
      .then(function(response){return response.json();})
      .then(function(response) {
        var trueTitle;
        if (typeof response.query.search[0] === 'undefined') trueTitle = "no page found";
        else trueTitle = response.query.search[0].title;
        state.vote = vote + " → " + trueTitle;
    });
    dispatch('sendVote', vote);
  },
  submitVote({ state, dispatch }, vote) {
    state.vote = vote;
    dispatch('sendVote', vote);
  },
  sendVote({ state }, vote) {
    var json:WebsocketPackage = {
      type: WebsocketPackageType.Vote,
      value: vote
    };
    state.ws?.send(JSON.stringify(json));
  },
  resetVote({ commit, state }) {
    commit('deleteVote');
    var json:WebsocketPackage = {
      type: WebsocketPackageType.ResetVote
    };
    state.ws?.send(JSON.stringify(json));
  },
  voteSkip({ state }) {
    var json:WebsocketPackage = {
      type: WebsocketPackageType.VoteSkip
    };
    state.ws?.send(JSON.stringify(json));
  },
  validateJump({ state }, data) {
    var json:WebsocketPackage = {
      type: WebsocketPackageType.Validate,
      value: data
    };
    state.ws?.send(JSON.stringify(json));
  },
  reset({ state }) {
    if (state.ws != null) state.ws.close(1000);
    state.ws = undefined;
    state.uuid = "";
    state.lang = Lang.en;
    state.lobbyType = LobbyType.Public;
    state.lobbyID = "";
    state.gamePhase = PhaseType.Voting;
    state.timeController.abort();
    state.timeController = new AbortController();
    state.round = 0;
    state.timeLeft = 0;
    state.timeStamp = 0;
    state.startPage = "";
    state.endPage = "";
    state.players = [];
    state.messages = [];
    state.winnerPageHistory = [];
    state.self = -1;
    state.owner = -2;
    state.winnerId = -3;
  }
};

interface WebsocketPackage {
  type:WebsocketPackageType,
  value?:String
}
enum WebsocketPackageType {
  Start = "Start",
  Message = "Message",
  Vote = "Vote",
  ResetVote = "ResetVote",
  Validate = "Validate",
  VoteSkip = "VoteSkip"
}


export enum LobbyEventType {
  SetOwner = "SetOwner",
  PlayerJoin = "PlayerJoin",
  PlayerLeft = "PlayerLeft",
  VoteResult = "VoteResult",
  GameState = "GameState",
  UpdateScore = "UpdateScore",
  WinRound = "WinRound",
  Message = "Message",
  Path = "Path",
  VoteSkip = "VoteSkip",
  Rollback = "Rollback"
}

export interface LobbyEvent<T> {
  type:LobbyEventType,
  data:T
}
export interface PlayerJoin {
  pseudo:string,
  id:number,//The player id
  score:number,
  voteSkip:boolean,
  self:boolean
}
export interface Path {
  id:number,//The player id
  pages:string[],
  time:number
}
export interface SetOwner {
  id:number//The player id
}
export interface PlayerLeft {
  id:number//The player id
}
export interface VoteResult {
  start:string,
  end:string
}
export interface VoteSkip {
  id:number, //The player id who skip
  state:boolean
}
export interface Rollback {
  page:string
}
export interface GameState {
  phase:number,
  round:number,
  time:number
}
export interface UpdateScore {
  id:number,//The player id
  score:number
}
export interface WinRound {
  id:number//The player id
}
export interface WsMessage {
  id:number,//The player id
  mes:string
}

export default actions;

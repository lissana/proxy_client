module Pool exposing (..)

-- connect somewhere through the gateway
-- and pool every 100ms

import Browser
import Html exposing (Html, text, pre, button, div)
import Html.Events exposing (onClick)
import Http
import Bytes exposing (Bytes)
import Task
import Time
import Url.Builder 

-- MAIN


main =
  Browser.element
    { init = init
    , update = update
    , subscriptions = subscriptions
    , view = view
    }



-- MODEL


type alias Model = 
    { connection : String
    , lastMsg : String
    , msg : String
    }

initial_model : Model
initial_model = 
    Model "" "" ""

init : () -> (Model, Cmd Msg)
init _ =
  ( initial_model 
  , Cmd.none 
  )

-- UPDATE


type Msg
  = ConnectRes (Result Http.Error String)
  | DisconnectRes (Result Http.Error String)
  | ReadRes (Result Http.Error String)
  | WriteRes (Result Http.Error String)
  | Tick Time.Posix
  | Connect
  | Disconnect


on_connect : Model -> (Model, Cmd Msg)
on_connect model =
    (model, write_conn model.connection "GET / HTTP/1.1\r\nHost: www.bing.com\r\n\r\n")

on_read : Model -> String -> (Model, Cmd Msg)
on_read model fullText =
    let isok = String.startsWith "ok;" fullText
        iserror = String.startsWith "error;" fullText
        len = String.length fullText
    in if isok then
         if len > 3 then
            ({ model | lastMsg = (String.slice 3 len fullText)}, Cmd.none)
         else
             (model, Cmd.none)
       else
         ({ model | msg = fullText}, Cmd.none)


update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    ConnectRes result ->
      case result of
        Ok fullText ->
          on_connect { model | connection = fullText , msg = "connected"}

        Err httperr ->
          case httperr of
              Http.BadStatus err ->
                ({ model | msg = "connect error - badstatus"}, Cmd.none)
              Http.BadBody err ->
                ({ model | msg = "connect error - badbody " ++ err}, Cmd.none)
              Http.NetworkError->
                ({ model | msg = "connect error - networkerror "}, Cmd.none)
              Http.BadUrl err ->
                ({ model | msg = "connect error - badurl " ++ err}, Cmd.none)
              _ ->
                ({ model | msg = "connect error "}, Cmd.none)


    ReadRes result ->
      case result of
        Ok fullText ->
          on_read model fullText 

        Err _ ->
          (model, Cmd.none)


    WriteRes result ->
      case result of
        Ok fullText ->
          (model, Cmd.none)

        Err _ ->
          (model, Cmd.none)


    Tick newTime ->
      ( model 
      , read_conn model.connection 
      )

    Connect ->
        ( model, connect "www.bing.com" 80)

    Disconnect ->
        ( {model | connection = ""}, disconnect model.connection )

    _ ->
          (model, Cmd.none)



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions model =
  Time.every 100 Tick



-- VIEW


view : Model -> Html Msg
view model =
    case model.connection of
        "" ->
          div []
            [ button [ onClick Connect ] [ text "connect" ]
            , div [] [ text model.msg ]
            , div [] [ text model.lastMsg ]
            ]
        _ ->
          div []
            [ button [ onClick Disconnect ] [ text "disconnect" ]
            , div [] [ text model.connection ]
            , div [] [ text model.msg ]
            , div [] [ text model.lastMsg ]
            ] 

makeReq action params = 
     Url.Builder.crossOrigin "http://127.0.0.1:9010" [action] params

connect : String -> Int -> Cmd Msg
connect host dport = 
    let uri = makeReq "connect" [
          Url.Builder.string "host" host
          , Url.Builder.int "port" dport
          ]
    in Http.get
           { url = uri 
           , expect = Http.expectString ConnectRes 
           }

disconnect token = 
  Http.get
      { url = "http://127.0.0.1:9010/disconnect?token=" ++ token
      , expect = Http.expectString DisconnectRes 
      }


read_conn token = 
   if token /= "" then
     Http.get
        { url = "http://127.0.0.1:9010/poll?token=" ++ token 
        , expect = Http.expectString ReadRes 
        }
   else
     Cmd.none

write_conn token data = 
    let 
        body = Http.stringBody "application/json" data 
    in Http.post
      { url = "http://127.0.0.1:9010/push?token=" ++ token 
      , body = body 
      , expect = Http.expectString WriteRes
      }



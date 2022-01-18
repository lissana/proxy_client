module Pool exposing (..)

-- connect somewhere through the gateway
-- and pool every 100ms

import Browser
import Html exposing (Html, text, pre)
import Http
import Bytes exposing (Bytes)


-- MAIN


main =
  Browser.element
    { init = init
    , update = update
    , subscriptions = subscriptions
    , view = view
    }



-- MODEL


type Model
  = Failure
  | Loading
  | Success String


init : () -> (Model, Cmd Msg)
init _ =
  ( Loading
  , Cmd.none 
  )

connect_cmd = 
  Http.get
      { url = "http://127.0.0.1:8081/connect?host=www.google.com&port=80"
      , expect = Http.expectString ConnectRes 
      }

read_conn = 
    let token = ""
    in Http.get
      { url = "http://127.0.0.1:8081/pool?token=" ++ token 
      , expect = Http.expectString ReadRes 
      }

write_conn data = 
    let token = ""
        body = Http.stringBody "application/json" data 
    in Http.post
      { url = "http://127.0.0.1:8081/push?token=" ++ token 
      , body = body 
      , expect = Http.expectString WriteRes
      }


-- UPDATE


type Msg
  = ConnectRes (Result Http.Error String)
  | ReadRes (Result Http.Error String)
  | WriteRes (Result Http.Error String)




update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    ConnectRes result ->
      case result of
        Ok fullText ->
          (Success fullText, Cmd.none)

        Err _ ->
          (Failure, Cmd.none)

    _ ->
          (Failure, Cmd.none)



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions model =
  Sub.none



-- VIEW


view : Model -> Html Msg
view model =
  case model of
    Failure ->
      text "I was unable to load your book."

    Loading ->
      text "Loading..."

    Success fullText ->
      pre [] [ text fullText ]

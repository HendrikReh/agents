open Lwt.Infix

module Log = Logging.OpenAI

module Message = struct
  type t = {
    role : string;
    content : string;
  }

  let to_yojson { role; content } =
    `Assoc [ "role", `String role; "content", `String content ]
end

type t = {
  api_key : string;
  default_model : string;
  base_url : string;
}

let default_base_url = "https://api.openai.com/v1"
let default_model = "gpt-5"

let create ?(model = default_model) ?(base_url = default_base_url) ~api_key () =
  Log.info (fun m -> m "Creating OpenAI client with model=%s, base_url=%s" model base_url);
  { api_key; default_model = model; base_url }

let endpoint t path =
  let base = Uri.of_string t.base_url in
  let current_path = Uri.path base in
  let combined_path =
    if current_path = "" || current_path = "/" then path else Filename.concat current_path path
  in
  Uri.with_path base combined_path

let headers t =
  Cohttp.Header.of_list
    [
      ("Authorization", "Bearer " ^ t.api_key);
      ("Content-Type", "application/json");
    ]

let handle_response (resp, body) =
  Cohttp_lwt.Body.to_string body >>= fun body_str ->
  let status = Cohttp.Response.status resp in
  let code = Cohttp.Code.code_of_status status in
  if Cohttp.Code.is_success code then (
    Log.debug (fun m -> m "OpenAI request successful (status=%d)" code);
    Lwt.return_ok body_str)
  else (
    Log.err (fun m -> m "OpenAI request failed (%d): %s" code body_str);
    Lwt.return_error
      (Printf.sprintf "OpenAI request failed (%d): %s" code body_str))

let chat ?(temperature = 0.2) ?(model = None) t ~messages =
  let model_name = Option.value ~default:t.default_model model in
  let endpoint = endpoint t "chat/completions" in
  (* gpt-5 doesn't support temperature parameter, only default (1) *)
  let is_gpt5 = String.starts_with ~prefix:"gpt-5" model_name in
  let body_fields =
    let base = [
      "model", `String model_name;
      "stream", `Bool false;
      "messages", `List (List.map Message.to_yojson messages);
    ] in
    if is_gpt5 then
      base
    else
      ("temperature", `Float temperature) :: base
  in
  if is_gpt5 then
    Log.info (fun m -> m "Sending chat request (model=%s, temperature=default, messages=%d)"
      model_name (List.length messages))
  else
    Log.info (fun m -> m "Sending chat request (model=%s, temperature=%.2f, messages=%d)"
      model_name temperature (List.length messages));
  let body = `Assoc body_fields |> Yojson.Safe.to_string in
  let body = Cohttp_lwt.Body.of_string body in
  Cohttp_lwt_unix.Client.post ~headers:(headers t) ~body endpoint
  >>= handle_response
  >>= function
  | Error _ as err -> Lwt.return err
  | Ok body_str -> (
      try
        let json = Yojson.Safe.from_string body_str in
        let open Yojson.Safe.Util in
        let choices = json |> member "choices" |> to_list in
        match choices with
        | [] ->
            Log.err (fun m -> m "OpenAI response missing choices");
            Lwt.return_error "OpenAI response missing choices"
        | choice :: _ ->
            let content =
              choice
              |> member "message"
              |> member "content"
              |> to_string
            in
            Log.debug (fun m -> m "Received response content (%d chars)" (String.length content));
            Lwt.return_ok content
      with Yojson.Json_error msg ->
        Log.err (fun m -> m "Failed to parse OpenAI JSON: %s" msg);
        Lwt.return_error ("Failed to parse OpenAI JSON: " ^ msg)
    )

let response_json ?temperature ?model t ~messages =
  chat ?temperature ?model t ~messages
  >>= function
  | Error _ as err -> Lwt.return err
  | Ok text -> (
      try Lwt.return_ok (Yojson.Safe.from_string text)
      with Yojson.Json_error msg -> Lwt.return_error ("Failed to decode JSON payload: " ^ msg)
    )

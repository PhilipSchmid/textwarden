# TextWarden for WeChat on macOS

TextWarden checks spelling and grammar in the focused message composer in WeChat (`com.tencent.xinWeChat`). The integration recognizes the `chat_input_field` accessibility identifier. Search and chat history are outside the integration.

`WeChatContentParser` reads the draft with its line breaks intact. TextWarden uses the composer's UTF-16 range bounds for inline underlines. `WeChatBehavior` enables corrections through a validated selection and pastes into the composer, so WeChat handles the edit and Undo. When sending or deleting clears the draft, TextWarden clears the old findings.

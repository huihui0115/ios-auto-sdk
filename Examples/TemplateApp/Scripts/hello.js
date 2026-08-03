auto.toast("AutoSDK ready");
auto.sleep(100);
auto.click({label: "登录", type: "Button"});
const title = auto.getText({id: "welcome-title"});
auto.toast("title: " + title);

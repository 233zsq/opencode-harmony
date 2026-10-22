"use strict";
(async function () {
  const mode = document.body.dataset.mode;
  const fragment = new URLSearchParams(location.hash.slice(1));
  let setupToken = fragment.get("token") || "";
  if (location.hash) history.replaceState(null, "", location.pathname);
  const form = document.getElementById("account-form");
  const message = document.getElementById("message");
  const notice = document.getElementById("notice");
  let csrf = "";
  async function api(path, data, extra) {
    const options = {method:data ? "POST" : "GET", credentials:"same-origin", cache:"no-store",
      headers:Object.assign(data ? {"Content-Type":"application/json", "X-CSRF-Token":csrf} : {}, extra || {})};
    if (data) options.body = JSON.stringify(data);
    const response = await fetch(path, options);
    const result = await response.json();
    if (!response.ok) throw new Error(result.error || "操作失败，请稍后重试");
    return result;
  }
  function tell(text) { message.textContent = text; }
  try {
    const state = await api("/auth/status");
    csrf = state.csrf;
    if (mode === "setup" && state.initialized) { location.replace("/login"); return; }
    if (mode === "setup" && !setupToken) {
      notice.textContent = "请通过服务器所有者的专属链接进行首次设置。";
      notice.hidden = false; return;
    }
    if (mode === "login" && !state.initialized) {
      notice.textContent = "账号尚未初始化，请使用专属链接完成设置。";
      notice.hidden = false; return;
    }
    if (form) form.hidden = false;
    const logout = document.getElementById("logout");
    if (logout) {
      logout.disabled = false;
      logout.addEventListener("click", async function () {
        logout.disabled = true;
        try { await api("/auth/logout", {}); location.replace("/login"); }
        catch (error) { tell(error.message); logout.disabled = false; }
      });
    }
  } catch (error) { tell("暂时无法连接，请刷新页面重试。"); return; }
  const visibility = document.getElementById("visibility");
  if (visibility) visibility.addEventListener("click", function () {
    const field = document.getElementById("password");
    const show = field.type === "password";
    field.type = show ? "text" : "password";
    visibility.textContent = show ? "隐藏" : "显示";
    visibility.setAttribute("aria-label", show ? "隐藏密码" : "显示密码");
    visibility.setAttribute("aria-pressed", String(show));
  });
  if (form) form.addEventListener("submit", async function (event) {
    event.preventDefault();
    if (!form.reportValidity()) return;
    const button = document.getElementById("submit");
    const data = {username:form.elements.username.value, password:form.elements.password.value};
    if (mode === "setup") data.confirmation = form.elements.confirmation.value;
    button.disabled = true; tell("");
    try {
      await api(mode === "setup" ? "/auth/setup" : "/auth/login", data,
        mode === "setup" ? {"X-Setup-Token":setupToken} : {});
      setupToken = "";
      form.reset();
      location.replace("/");
    } catch (error) { tell(error.message); button.disabled = false; }
    finally { data.password = ""; data.confirmation = ""; }
  });
}());

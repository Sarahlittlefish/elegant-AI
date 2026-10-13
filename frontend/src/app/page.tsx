"use client";
import React, { useState, useEffect, useRef } from "react";
import { Send } from "lucide-react";

interface ChatMessage {
  id: string;
  sender: "user" | "kai";
  content: string;
}

// 聊天记录存在浏览器里（换了新的 key，旧版页面留下的记录不会带进来）
const HISTORY_KEY = "chat_history_v2";

// 开场：她当年随手丢进 @/ 的两条剪贴板，对方回了一个「?」
const OPENING: ChatMessage[] = [
  { id: "open_0", sender: "user", content: "(3.6-4.3)发饰跟随曲线头发v1.0 提取码: qsmv" },
  { id: "open_1", sender: "user", content: "¡™£¢∞§¶•ªº–≠«‘“πøˆ¨¥†®´∑œåßƒ©˙∆˚¬…æ÷≥≤µ˜∫√ç√" },
  { id: "open_2", sender: "kai", content: "?" },
];

export default function ChatPage() {
  const [messages, setMessages] = useState<ChatMessage[]>(OPENING);
  const [inputValue, setInputValue] = useState("");
  const [isLoading, setIsLoading] = useState(false);
  const [apiKey, setApiKey] = useState("");
  const messagesEndRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    setApiKey(localStorage.getItem("companion_api_key") || "");
    const saved = localStorage.getItem(HISTORY_KEY);
    if (saved) {
      try {
        const parsed = JSON.parse(saved);
        if (Array.isArray(parsed) && parsed.length > 0) setMessages(parsed);
      } catch {
        // 记录坏了就从开场重新开始
      }
    }
  }, []);

  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages, isLoading]);

  const handleSendMessage = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!inputValue.trim() || isLoading) return;
    const userMsg: ChatMessage = {
      id: `u_${Date.now()}`,
      sender: "user",
      content: inputValue.trim(),
    };
    setInputValue("");
    const updated = [...messages, userMsg];
    setMessages(updated);
    localStorage.setItem(HISTORY_KEY, JSON.stringify(updated));
    setIsLoading(true);
    try {
      const response = await fetch("/api/chat", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          messages: updated
            .filter((m) => !m.id.startsWith("err_"))
            .map((m) => ({ sender: m.sender, content: m.content })),
          clientApiKey: apiKey,
        }),
      });
      const data = await response.json();
      if (!response.ok) throw new Error(data.error || "请求失败");
      // 对方用空行隔开的几句话，当成连发的几条消息
      const parts = String(data.reply)
        .split(/\n\s*\n/)
        .map((s) => s.trim())
        .filter(Boolean);
      const replies: ChatMessage[] = parts.map((content, i) => ({
        id: `k_${Date.now()}_${i}`,
        sender: "kai",
        content,
      }));
      const final = [...updated, ...replies];
      setMessages(final);
      localStorage.setItem(HISTORY_KEY, JSON.stringify(final));
    } catch (err: any) {
      setMessages((prev) => [
        ...prev,
        {
          id: `err_${Date.now()}`,
          sender: "kai",
          content: `[消息没发出去: ${err.message || "网络异常"}]`,
        },
      ]);
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <div className="flex flex-col h-dvh bg-white text-neutral-900">
      <header className="flex items-center gap-3 px-4 py-3 border-b border-neutral-200">
        <div className="w-9 h-9 rounded-full bg-neutral-900 text-white flex items-center justify-center text-sm font-semibold">
          @/
        </div>
        <h1 className="text-base font-semibold">@/</h1>
      </header>

      <main className="flex-1 overflow-y-auto px-4 py-4 space-y-2 max-w-2xl w-full mx-auto">
        {messages.map((msg) => {
          const isUser = msg.sender === "user";
          return (
            <div key={msg.id} className={`flex ${isUser ? "justify-end" : "justify-start"}`}>
              <p
                className={`max-w-[80%] px-4 py-2 rounded-2xl text-[15px] leading-relaxed whitespace-pre-wrap break-words ${
                  isUser
                    ? "bg-blue-500 text-white rounded-br-md"
                    : "bg-neutral-100 text-neutral-900 rounded-bl-md"
                }`}
              >
                {msg.content}
              </p>
            </div>
          );
        })}
        {isLoading && (
          <div className="flex justify-start">
            <p className="px-4 py-2 rounded-2xl rounded-bl-md bg-neutral-100 text-neutral-400 text-[15px]">
              ...
            </p>
          </div>
        )}
        <div ref={messagesEndRef} />
      </main>

      <footer className="px-3 py-3 border-t border-neutral-200">
        <form onSubmit={handleSendMessage} className="max-w-2xl mx-auto flex items-center gap-2">
          <input
            type="text"
            value={inputValue}
            onChange={(e) => setInputValue(e.target.value)}
            placeholder="发消息"
            className="flex-1 px-4 py-2.5 text-[15px] bg-neutral-100 rounded-full focus:outline-none focus:ring-2 focus:ring-blue-400"
          />
          <button
            type="submit"
            disabled={isLoading || !inputValue.trim()}
            aria-label="发送"
            className="p-2.5 bg-blue-500 text-white rounded-full disabled:opacity-40"
          >
            <Send className="w-4 h-4" />
          </button>
        </form>
      </footer>
    </div>
  );
}

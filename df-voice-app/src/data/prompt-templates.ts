import type { PromptTemplate } from "@/types/client";

export const promptTemplates: PromptTemplate[] = [
  {
    id: "clean-transcript",
    name: "逐字稿整理",
    category: "Transcript",
    description: "保留原意，修正口語斷句、標點與明顯錯字，輸出乾淨可讀版本。",
    tags: ["cleanup", "zh-TW"],
    prompt:
      "請將下方語音逐字稿整理成繁體中文可讀稿。保留原意與專有名詞，不新增沒有出現在逐字稿中的資訊。輸出只包含整理後內容。",
  },
  {
    id: "meeting-summary",
    name: "會議摘要",
    category: "Meeting",
    description: "整理重點、決策、風險與待辦，適合會後直接貼到工作區。",
    tags: ["summary", "actions"],
    prompt:
      "請根據下方逐字稿產出繁體中文會議摘要，包含：重點摘要、已決策事項、待追蹤風險、下一步待辦。每個待辦請標出負責人；若逐字稿沒有提到負責人，標示「未指定」。",
  },
  {
    id: "action-items",
    name: "待辦萃取",
    category: "Operations",
    description: "把口述內容轉成可執行 checklist，避免重要工作散在長篇文字裡。",
    tags: ["tasks", "checklist"],
    prompt:
      "請從下方逐字稿萃取可執行待辦，使用繁體中文 checklist。每個項目需包含動作、背景、期限；若期限未知，標示「未指定」。不要加入逐字稿沒有支持的事項。",
  },
  {
    id: "reply-draft",
    name: "回覆草稿",
    category: "Communication",
    description: "把口述想法整理成清楚、禮貌、可直接送出的訊息。",
    tags: ["draft", "message"],
    prompt:
      "請根據下方口述內容，撰寫一則繁體中文回覆草稿。語氣直接、禮貌、專業，保留必要脈絡，避免過度客套。",
  },
  {
    id: "english-brief",
    name: "英文簡報稿",
    category: "Translation",
    description: "將中文口述整理成自然英文 brief，適合寄給跨國團隊。",
    tags: ["english", "brief"],
    prompt:
      "Please turn the transcript below into a concise English brief. Preserve names, product terms, numbers, and decisions. Use clear business English and do not add unsupported details.",
  },
];

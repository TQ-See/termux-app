package.path = package.path  .. ";/data/data/com.termux/files/home/.local/share/?.lua"

-- ================= KONFIGURASI =================
local config = require("env")
local api_key = config.keys.gemini

-- Cek apakah berhasil load API Key
if not api_key then
    print("[Error]: API Key tidak ditemukan di env.lua")
    os.exit()
end

local model_name = "gemini-2.5-flash"
local endpoint = "https://generativelanguage.googleapis.com/v1beta/models/" .. model_name .. ":generateContent?key=" .. api_key

-- FILE PATHS
local history_file = "/data/data/com.termux/files/home/.local/share/json/chat_history.json"
local payload_file = "/data/data/com.termux/files/home/.local/share/json/payload.json"
local response_file = "/data/data/com.termux/files/home/.local/share/json/response.json"

-- INSTRUKSI SISTEM
local system_prompt = "Jawablah selalu menggunakan paragraf yang singkat dan to the point. Hindari pembahasan yang bertele-tele dan penggunaan daftar (bullet points/numbering) kecuali benar-benar dibutuhkan secara eksplisit. Gunakan bahasa Indonesia yang santai tapi jelas."

-- ================= FUNGSI BANTUAN =================

-- Fungsi untuk menjalankan perintah shell dan membaca outputnya
local function shell_exec(cmd)
    local handle = io.popen(cmd)
    local result = handle:read("*a")
    handle:close()
    return result:gsub("^%s*(.-)%s*$", "%1") -- Trim whitespace/newline
end

-- Cek apakah file history ada, jika tidak buat baru
local f = io.open(history_file, "r")
if not f then
    os.execute("echo '[]' > " .. history_file)
else
    f:close()
end

-- ================= LOGIKA UTAMA =================

-- 1. Ambil Pesan User
local user_message = arg[1]
if not user_message then 
    print("Gunakan: lua gemini.lua \"pesan anda\" atau \"rechat\" atau \"reset\"")
    os.exit() 
end

-- [FITUR BARU] Cek perintah RESET
if string.lower(user_message) == "reset" then
    os.execute("echo '[]' > " .. history_file)
    print("[System]: Riwayat percakapan telah dihapus.")
    os.exit()
end

-- [FITUR BARU] Cek perintah RECHAT (Tampilkan History)
if string.lower(user_message) == "rechat" then
    print("\n--- MEMUAT RIWAYAT PERCAKAPAN ---\n")
    
    -- Kita pakai jq untuk format langsung biar rapi dan cepat
    -- Logika jq: Loop array, cek role (user/model), lalu print teksnya
    local cmd_rechat = string.format(
        "jq -r '.[] | if .role == \"user\" then \"\\n[You] :\" else \"\\n[Gemini] :\" end, .parts[0].text' %s", 
        history_file
    )
    
    local history_log = shell_exec(cmd_rechat)
    
    if history_log == "" then
        print("[System]: Belum ada riwayat chat.")
    else
        print(history_log)
        print("\n---------------------------------")
        print("[End of History]")
    end
    os.exit()
end

-- 2. Update History (User)
local safe_msg = string.format("%q", user_message)
local cmd_update_user = string.format(
    "jq --arg txt %s '. += [{\"role\": \"user\", \"parts\": [{\"text\": $txt}]}]' %s > tmp.json && mv tmp.json %s", 
    safe_msg, history_file, history_file
)
os.execute(cmd_update_user)

-- 3. Siapkan Payload (Memasukkan System Instruction)
local cmd_payload = string.format(
    "jq --arg inst %q '{systemInstruction: {parts: [{text: $inst}]}, contents: .}' %s > %s",
    system_prompt, history_file, payload_file
)
os.execute(cmd_payload)

-- 4. Kirim Request dengan CURL
-- (Menambahkan animasi loading titik sederhana agar tidak terlihat hang)
-- io.write("Gemini sedang mengetik...")
local cmd_curl = string.format(
    "curl -s -X POST %q -H 'Content-Type: application/json' -d @%s > %s",
    endpoint, payload_file, response_file
)
os.execute(cmd_curl)
io.write("\r" .. string.rep(" ", 25) .. "\r") -- Hapus teks loading

-- 5. Ambil Jawaban & Token dengan jq
local answer = shell_exec("jq -r '.candidates[0].content.parts[0].text // empty' " .. response_file)
local token_count = shell_exec("jq -r '.usageMetadata.totalTokenCount // 0' " .. response_file)
local error_msg = shell_exec("jq -r '.error.message // empty' " .. response_file)

-- 6. Tampilkan Hasil
if error_msg ~= "" then
    print("\n[Error]: " .. error_msg)
elseif answer == "" then
    print("\n[Error]: Tidak ada respon dari API.")
else
    print("Gemini :")
    print(answer)
    print("") 
    print("[Realtime Token: " .. token_count .. "]")

    -- 7. Simpan Jawaban Gemini ke History
    local safe_answer = string.format("%q", answer)
    local cmd_update_model = string.format(
        "jq --arg txt %s '. += [{\"role\": \"model\", \"parts\": [{\"text\": $txt}]}]' %s > tmp.json && mv tmp.json %s",
        safe_answer, history_file, history_file
    )
    os.execute(cmd_update_model)
end

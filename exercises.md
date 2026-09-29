# Phiếu Phản Ánh — K4 Level 3B, Ngày 12

> **Bài làm cá nhân.** Trả lời bằng lời của chính bạn, dựa trên những gì bạn
> quan sát được khi chạy code — không sao chép đáp án của người khác.
>
> Cách trả lời: thay dòng placeholder bằng câu trả lời của bạn.
> `grade.py` đếm số câu đã trả lời (15 điểm cho 10 câu).
>
> Họ và tên: Ngô Anh Khoa  Mã học viên: 2A202602965

---

### Câu 1 — Fail fast (CP1)

Trong `Settings`, `agent_api_key` không có giá trị mặc định nên app chết ngay
khi khởi động nếu thiếu biến môi trường. Hãy mô tả một tình huống cụ thể mà
việc "chết sớm" này cứu bạn, so với việc để mặc định `"changeme"`.

> Khi deploy lên Railway, nếu quên set biến `AGENT_API_KEY` trong dashboard mà `agent_api_key` có mặc định `"changeme"`, app vẫn khởi động bình thường. Lúc này bất kỳ ai biết giá trị mặc định đều có thể gọi `/ask` và tiêu hết ngân sách LLM của mình mà mình không hay biết — chỉ phát hiện khi nhìn hóa đơn. Ngược lại, khi không có mặc định, pydantic-settings ném `ValidationError` ngay lúc khởi động, container fail và log hiện rõ "agent_api_key Field required". Mình thấy lỗi ngay trên dashboard khi đang nhìn màn hình, sửa lại rồi deploy lại mất chưa đến 1 phút. Fail fast giúp phát hiện lỗi cấu hình ở thời điểm an toàn nhất — lúc deploy, không phải lúc đang chạy production.

---

### Câu 2 — Log cho máy đọc (CP1)

Chạy service và gọi `/ask` vài lần. Dán một dòng log JSON bạn thu được, rồi
nêu **hai** việc bạn làm được với dòng log đó mà `print("đã trả lời xong")`
không làm được.

> Một dòng log JSON thu được: `{"event": "ask_completed", "level": "info", "timestamp": "2026-09-29T02:30:00+00:00", "user_id": "sv01", "tokens_in": 5, "tokens_out": 42, "cost_usd": 2.59e-05}`
>
> Hai việc làm được mà `print()` không:
> 1. **Lọc theo user_id**: Trên hệ thống log tập trung (Datadog, CloudWatch), mình có thể query `user_id = "sv01"` để xem tất cả request của user đó, tính tổng chi phí trong ngày. Với `print("đã trả lời xong")` thì không có trường nào để lọc.
> 2. **Cảnh báo tự động**: Có thể đặt alert khi `cost_usd` vượt ngưỡng hoặc khi tỷ lệ event `"error"` trong 5 phút qua vượt 5%, vì mỗi dòng log đều có trường `level` và `cost_usd` dạng số. `print()` trả về chuỗi tự do, máy không parse được.

---

### Câu 3 — Kích thước image (CP2)

Build cả hai phiên bản và ghi lại số đo thật:

```bash
docker build -f <Dockerfile-1-stage> -t agent:single .
docker build -t agent:multi .
docker images | grep agent
```

| Bản | Dung lượng |
|-----|-----------|
| 1 stage (bản đầu) | ~1.05 GB |
| Multi-stage | ~210 MB |

Giải thích: phần dung lượng chênh lệch đó là những gì?

> Phần chênh lệch ~840MB chủ yếu là: (1) base image `python:3.11` đầy đủ chứa nhiều thư viện hệ thống (gcc, build-essential, dev headers) mà runtime không cần — bản `slim` chỉ giữ những gì cần để chạy Python; (2) các file tạm và cache của pip trong quá trình biên dịch packages (ví dụ: header files, object files `.o`, pip cache); (3) toàn bộ build context không cần thiết (tests, screenshots, .git, markdown files) bị COPY vào do bản cũ dùng `COPY . .`. Multi-stage chỉ COPY kết quả đã cài (`/install`) sang stage runtime, mọi thứ trung gian bị vứt đi.

---

### Câu 4 — Thứ tự lệnh trong Dockerfile (CP2)

Sửa một ký tự trong `app/main.py` rồi build lại. Với Dockerfile của bạn, những
layer nào được dùng lại từ cache, layer nào phải chạy lại? Nếu bạn đặt
`COPY . .` lên trước `RUN pip install` thì kết quả khác thế nào?

> Với Dockerfile hiện tại (COPY requirements.txt → pip install → COPY app), khi sửa 1 ký tự trong `app/main.py`:
> - **Cache HIT**: `FROM python:3.11-slim`, `COPY requirements.txt .`, `RUN pip install` — tất cả được dùng lại vì `requirements.txt` không đổi.
> - **Cache MISS**: Chỉ `COPY app ./app` trở đi phải chạy lại — rất nhanh vì chỉ copy file.
>
> Nếu đặt `COPY . .` trước `pip install`: Docker thấy bất kỳ file nào thay đổi (kể cả 1 dấu phẩy trong `main.py`) → layer `COPY . .` bị invalidate → mọi layer sau nó (bao gồm `pip install`) đều phải chạy lại. Kết quả: mỗi lần sửa code, phải cài lại toàn bộ thư viện, mất thêm vài phút mỗi lần build.

---

### Câu 5 — Vì sao không chạy bằng root (CP2)

Container mặc định chạy bằng root. Mô tả chuỗi sự kiện dẫn từ "một lỗ hổng
trong code Python của bạn" tới "kẻ tấn công có quyền cao trên máy host", và
lệnh `USER` cắt đứt chuỗi đó ở chỗ nào.

> Chuỗi sự kiện: (1) App Python có lỗ hổng Server-Side Request Forgery hoặc Remote Code Execution (ví dụ: deserialize input không an toàn). (2) Kẻ tấn công gửi payload khai thác lỗ hổng, chạy được lệnh shell bên trong container. (3) Vì container chạy root, lệnh shell chạy với quyền root. (4) Kẻ tấn công đọc được `/etc/shadow`, cài thêm công cụ, và nếu Docker daemon cấu hình sai (không dùng user namespace) hoặc có lỗ hổng container escape, quyền root trong container có thể trở thành quyền root trên máy host.
>
> Lệnh `USER appuser` cắt đứt ở bước (3): dù kẻ tấn công chạy được lệnh shell, lệnh đó chạy với quyền `appuser` (uid 10001) — không đọc được file nhạy cảm, không cài thêm package, không thay đổi cấu hình hệ thống. Thiệt hại bị giới hạn ở phạm vi ứng dụng, không lan ra host.

---

### Câu 6 — Cửa sổ trượt (CP3)

Rate limit của bạn dùng sliding window 60 giây. Nếu thay bằng cách đếm theo
phút đồng hồ (reset lúc giây 00), một người dùng có thể gửi tối đa bao nhiêu
request trong 2 giây liên tiếp khi hạn mức là 10/phút? Giải thích cách đạt được
con số đó.

> Tối đa **20 request trong 2 giây**. Cách đạt được: gửi 10 request vào lúc 10:00:59 (vẫn nằm trong phút 10:00, bộ đếm = 10, vừa đúng limit). Sang giây 10:01:00, bộ đếm theo phút đồng hồ reset về 0. Gửi tiếp 10 request lúc 10:01:01 (bộ đếm phút mới = 10, vẫn "đúng luật"). Kết quả: 20 request trong khoảng 2 giây (từ 10:00:59 đến 10:01:01) mà không vi phạm rate limit. Sliding window không có lỗ hổng này vì nó luôn nhìn lại đúng 60 giây gần nhất — 10 request cũ vẫn còn trong cửa sổ nên request thứ 11 bị chặn.

---

### Câu 7 — Rate limit và cost guard (CP3)

Hai cơ chế này khác nhau ở điểm nào? Cho một tình huống mà rate limit cho qua
nhưng cost guard phải chặn, và một tình huống ngược lại.

> **Khác nhau**: Rate limit giới hạn **tần suất** (số request/phút), cost guard giới hạn **chi phí** (USD/tháng). Rate limit đếm số lần gọi bất kể nội dung, cost guard đếm tổng tiền bất kể tốc độ gọi.
>
> **Rate limit cho qua, cost guard chặn**: User gửi 5 request/phút (dưới limit 10), nhưng mỗi request chứa prompt 50.000 token (cost ~$0.50/request). Sau 20 request trong 4 phút, tổng chi phí đã vượt $10 budget/tháng. Rate limit không chặn vì chỉ có 5 req/phút, nhưng cost guard chặn vì hết ngân sách.
>
> **Cost guard cho qua, rate limit chặn**: User gửi 15 request/phút nhưng mỗi request rất ngắn ("Hi"), cost mỗi request chỉ ~$0.00001. Tổng chi phí rất thấp (cost guard cho qua), nhưng rate limit chặn vì vượt 10 req/phút — bảo vệ server khỏi bị quá tải.

---

### Câu 8 — /health khác /ready (CP4)

Nếu gộp hai endpoint làm một và cho nó kiểm tra Redis, chuyện gì xảy ra với cụm
3 container khi Redis mất kết nối 30 giây? Trả lời theo đúng thứ tự sự kiện.

> Thứ tự sự kiện khi gộp `/health` kiểm tra Redis:
> 1. Redis mất kết nối (ví dụ: network blip 30 giây).
> 2. Health check của cả 3 container gọi Redis → timeout → trả 503.
> 3. Orchestrator (Docker/K8s) thấy cả 3 container "unhealthy" → quyết định restart cả 3 cùng lúc.
> 4. Trong khi 3 container đang restart (mất ~10-20 giây mỗi container), không còn container nào sống để phục vụ request → user thấy 502/503 hàng loạt.
> 5. Redis quay lại sau 30 giây, nhưng cả 3 container vẫn đang trong quá trình khởi động lại.
> 6. Sự cố nhỏ (Redis blip 30s) biến thành sự cố lớn (toàn bộ service down 30-60s).
>
> Nếu tách: `/health` không check Redis → orchestrator không restart → `/ready` trả 503 → LB ngừng gửi request → Redis quay lại → `/ready` trả 200 → service hoạt động bình thường, user không thấy gì.

---

### Câu 9 — Stateless (CP4)

Chạy `docker compose up --scale agent=3` rồi gọi `/ask` nhiều lần với cùng một
`X-User-Id`. Quan sát `history_length` trong response. Nếu lịch sử được lưu
trong một dict Python thay vì Redis, bạn sẽ thấy con số đó thay đổi thế nào?

> Với Redis (hiện tại): `history_length` tăng đều đặn 0, 2, 4, 6, 8... (mỗi request thêm 2 message: user + assistant) bất kể request vào container nào, vì cả 3 container cùng đọc/ghi một Redis.
>
> Nếu dùng dict Python: `history_length` sẽ nhảy **không đều và lặp lại**. Ví dụ: request 1 vào container A → history_length=0. Request 2 vào container B → history_length=0 (B không biết gì về A). Request 3 lại vào A → history_length=2. Request 4 vào C → history_length=0. Con số nhảy lung tung vì mỗi container có dict riêng, load balancer gửi request ngẫu nhiên. Agent dường như "mất trí nhớ" một cách ngẫu nhiên — user rất bối rối.

---

### Câu 10 — Deploy thật (CP5)

Ghi lại **một** lỗi bạn gặp khi deploy lên cloud (build fail, health check
timeout, sai REDIS_URL, app không đọc `$PORT`...): thông báo lỗi là gì, bạn
tìm ra nguyên nhân bằng cách nào, và sửa ra sao?

> Lỗi gặp: Sau khi deploy lên Railway, service khởi động thành công nhưng health check liên tục timeout và service bị restart lặp lại. Log trên Railway hiển thị `INFO: Uvicorn running on http://127.0.0.1:8000`.
>
> Nguyên nhân: Uvicorn đang bind vào `127.0.0.1` (localhost) thay vì `0.0.0.0`. Trong container, `127.0.0.1` chỉ có thể truy cập từ bên trong container, health check của Railway gọi từ bên ngoài nên không kết nối được.
>
> Cách tìm ra: Đọc log trên dashboard Railway, thấy dòng `running on http://127.0.0.1:8000` → nhận ra sai host. Đối chiếu với Dockerfile: CMD dùng `--host 0.0.0.0` nhưng ban đầu mình quên sửa.
>
> Cách sửa: Đảm bảo CMD trong Dockerfile dùng `--host 0.0.0.0 --port ${PORT:-8000}`. Sau khi sửa và push lại, Railway tự build lại và health check pass.

# Lab thực hành: CloudNativePG HA + Failover + GitOps trên Windows 10 + Docker Desktop
### Phase 1: Dựng HA (1 Primary + 2 Replica) — Phase 2: Mô phỏng Failover — Phase 3: GitOps Schema Sync với ArgoCD

> **Minh bạch trước khi bắt đầu:** Sandbox của mình không có Kubernetes để chạy thử trực tiếp, nên các bước dưới đây **chưa được chạy thật để kiểm chứng** như các use case Docker đơn giản trước — nhưng được viết chính xác theo đúng tài liệu chính thức của kind, CloudNativePG (bản 1.29.x hiện tại), và ArgoCD mà mình đã tra cứu lại. Nếu 1 lệnh nào đó báo lỗi khác với mô tả, khả năng cao là do phiên bản phần mềm đã cập nhật — cứ dán lỗi cho mình, mình sẽ giúp bạn debug tiếp theo đúng phiên bản bạn đang có.

---

## Chuẩn bị môi trường (làm 1 lần)

### Bước 0.1 — Cài `kubectl`

Mở PowerShell (không cần Admin):
```powershell
winget install -e --id Kubernetes.kubectl
```
Kiểm tra:
```powershell
kubectl version --client
```

### Bước 0.2 — Cài `kind` (Kubernetes in Docker — chạy Kubernetes ngay trên Docker Desktop đã có)

```powershell
winget install -e --id Kubernetes.kind
```
Kiểm tra:
```powershell
kind version
```

### Bước 0.3 — Đảm bảo Docker Desktop đang chạy

Mở Docker Desktop, chờ đến khi thấy "Engine running" (đã làm ở tài liệu trước).

### Bước 0.4 — Tạo thư mục làm việc cho lab

```powershell
mkdir C:\gitops-cnpg-lab
cd C:\gitops-cnpg-lab
mkdir k8s-manifests
mkdir db-migrations
```
Copy toàn bộ file đính kèm vào đúng vị trí tương ứng.

---

## PHASE 1 — Dựng HA Cluster: 1 Primary + 2 Replica với CloudNativePG

### Bước 1.1 — Tạo cluster Kubernetes bằng `kind` (giả lập nhiều "server" bằng nhiều node ảo)

Để mô phỏng thực tế gần hơn (không chỉ 1 node duy nhất), tạo file cấu hình kind với 1 control-plane + 3 worker node — đủ để CloudNativePG dàn 3 Pod Postgres ra 3 node khác nhau:

```powershell
@"
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
  - role: worker
  - role: worker
  - role: worker
"@ | Out-File -Encoding utf8 C:\gitops-cnpg-lab\kind-config.yaml
```

Tạo cluster:
```powershell
kind create cluster --name pg-lab --config C:\gitops-cnpg-lab\kind-config.yaml
```

→ Lệnh chạy khoảng 1-2 phút (kind tải image node Kubernetes lần đầu). Kết quả cuối cùng phải có dòng:
```
Set kubectl context to "kind-pg-lab"
You can now use your cluster with:

kubectl cluster-info --context kind-pg-lab
```

Xác nhận có đúng 4 node (1 control-plane + 3 worker):
```powershell
kubectl get nodes
```

### Bước 1.2 — Cài đặt CloudNativePG Operator

```powershell
kubectl apply --server-side -f https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.29/releases/cnpg-1.29.2.yaml
```

*(Nếu link này báo lỗi 404 do phiên bản đã thay đổi kể từ khi viết tài liệu, vào https://github.com/cloudnative-pg/cloudnative-pg/releases để lấy đúng link file `cnpg-x.y.z.yaml` mới nhất.)*

Chờ operator khởi động xong:
```powershell
kubectl rollout status deployment -n cnpg-system cnpg-controller-manager
```
→ Kết quả đúng: `deployment "cnpg-controller-manager" successfully rolled out`

### Bước 1.3 — Tạo namespace cho database

```powershell
kubectl create namespace insurance-system
```

### Bước 1.4 — Áp dụng Cluster CR (1 Primary + 2 Replica)

File `k8s-manifests/01-cnpg-cluster.yaml` (đã có sẵn trong bộ file đính kèm):
```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: insurance-db
  namespace: insurance-system
spec:
  instances: 3   # 1 primary tu dong bau + 2 replica

  bootstrap:
    initdb:
      database: pocdb
      owner: app_user

  storage:
    size: 1Gi
    storageClass: standard

  resources:
    requests:
      memory: "256Mi"
      cpu: "250m"
    limits:
      memory: "512Mi"
      cpu: "500m"
```

Áp dụng:
```powershell
kubectl apply -f C:\gitops-cnpg-lab\k8s-manifests\01-cnpg-cluster.yaml
```

### Bước 1.5 — Theo dõi quá trình bootstrap

```powershell
kubectl get pods -n insurance-system -w
```
→ Chờ đến khi thấy 3 Pod (`insurance-db-1`, `insurance-db-2`, `insurance-db-3`) đều chuyển sang `1/1 Running`. Nhấn `Ctrl+C` để thoát chế độ theo dõi khi cả 3 đã Running.

### Bước 1.6 — Cài `kubectl cnpg` plugin (công cụ chính thức để xem trạng thái cluster dễ đọc hơn)

```powershell
kind get kubeconfig --name pg-lab > $env:USERPROFILE\.kube\config
```
Tải plugin (Windows binary) theo hướng dẫn tại https://github.com/cloudnative-pg/cloudnative-pg/releases — tìm file `kubectl-cnpg_*_windows_amd64.zip`, giải nén, đặt `kubectl-cnpg.exe` vào 1 thư mục có trong `PATH`.

Kiểm tra trạng thái cluster:
```powershell
kubectl cnpg status insurance-db -n insurance-system
```

→ Kết quả đúng phải hiện rõ:
```
Cluster Summary
Name:               insurance-db
Namespace:          insurance-system
...
Instances status
Name             Current LSN   Replication role   Status
insurance-db-1   0/6000000     Primary            OK
insurance-db-2   0/6000000     Standby (async)    OK
insurance-db-3   0/6000000     Standby (async)    OK
```

**→ Đây là bằng chứng Phase 1 hoàn tất: 1 Primary + 2 Replica đang chạy, đều "OK".**

### Bước 1.7 — Xác nhận Pod Anti-Affinity hoạt động (3 Pod nằm trên 3 node khác nhau)

```powershell
kubectl get pods -n insurance-system -o wide
```
→ Cột `NODE` phải cho thấy 3 Pod nằm trên **3 worker node khác nhau** — CloudNativePG tự áp dụng anti-affinity mặc định.

### Bước 1.8 — Thử kết nối vào database

```powershell
kubectl get secret insurance-db-app -n insurance-system -o jsonpath="{.data.password}" | ForEach-Object { [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($_)) }
```
→ Copy password hiện ra, rồi mở port-forward để test:
```powershell
kubectl port-forward -n insurance-system svc/insurance-db-rw 5432:5432
```
Mở 1 cửa sổ PowerShell khác:
```powershell
psql -h localhost -p 5432 -U app_user -d pocdb
```
(nhập password vừa lấy được)

---

## PHASE 2 — Mô phỏng Failover

### Bước 2.1 — Xác định Pod nào đang là Primary

```powershell
kubectl cnpg status insurance-db -n insurance-system
```
→ Ghi lại tên Pod có `Replication role: Primary` (ví dụ `insurance-db-1`).

### Bước 2.2 — Ghi dữ liệu test trước khi làm sập Primary

Trong cửa sổ `psql` đang mở (Bước 1.8):
```sql
CREATE TABLE failover_test (id serial primary key, msg text, created_at timestamptz default now());
INSERT INTO failover_test (msg) VALUES ('Du lieu truoc khi failover');
SELECT * FROM failover_test;
```

### Bước 2.3 — Mô phỏng Primary sập hoàn toàn

Mở 1 cửa sổ PowerShell mới (giữ nguyên port-forward và psql đang chạy):

```powershell
kubectl delete pod insurance-db-1 -n insurance-system --grace-period=0 --force
```
*(Thay `insurance-db-1` bằng đúng tên Pod Primary bạn xác định ở Bước 2.1.)*

### Bước 2.4 — Theo dõi quá trình failover real-time

```powershell
kubectl get pods -n insurance-system -w
```
→ Quan sát: Pod primary cũ biến mất, Kubernetes tạo lại Pod mới (nhưng nó sẽ khởi động lại với vai trò **Replica**, không tự động là Primary), và 1 trong 2 replica còn lại **tự động được promote** thành Primary mới.

Đồng thời mở thêm 1 cửa sổ khác để xem log của operator lúc failover diễn ra:
```powershell
kubectl logs -n cnpg-system -l app.kubernetes.io/name=cloudnative-pg -f
```
→ Tìm dòng log dạng `Current primary isn't healthy, initiating a failover` và sau đó `Setting a new primary`.

### Bước 2.5 — Xác nhận failover hoàn tất

```powershell
kubectl cnpg status insurance-db -n insurance-system
```
→ Phải thấy 1 Pod khác (ví dụ `insurance-db-2`) giờ mang `Replication role: Primary`.

### Bước 2.6 — Xác nhận dữ liệu không mất và Service tự route đúng

Cửa sổ `psql` cũ (port-forward tới Service `insurance-db-rw`) có thể bị ngắt kết nối tạm thời trong lúc failover — kết nối lại:
```powershell
psql -h localhost -p 5432 -U app_user -d pocdb -c "SELECT * FROM failover_test;"
```
→ Dữ liệu `'Du lieu truoc khi failover'` vẫn còn nguyên — vì Service `insurance-db-rw` tự động trỏ lại đúng Primary mới, bạn **không cần đổi bất kỳ connection string nào**.

Thử ghi thêm dữ liệu mới vào Primary mới để chắc chắn:
```sql
INSERT INTO failover_test (msg) VALUES ('Da ghi thanh cong vao Primary MOI sau failover');
SELECT * FROM failover_test;
```

**→ Đây là bằng chứng Phase 2 hoàn tất.**

---

## PHASE 3 — GitOps: ArgoCD + Git tự động đồng bộ Schema

### Bước 3.1 — Cài đặt ArgoCD vào cluster

```powershell
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

Chờ ArgoCD khởi động xong:
```powershell
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd
```

### Bước 3.2 — Truy cập giao diện ArgoCD

Mở port-forward:
```powershell
kubectl port-forward svc/argocd-server -n argocd 8080:443
```
Mở trình duyệt: **https://localhost:8080** (chấp nhận cảnh báo chứng chỉ tự ký).

Lấy mật khẩu admin mặc định:
```powershell
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | ForEach-Object { [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($_)) }
```
Đăng nhập với username `admin` và password vừa lấy được.

### Bước 3.3 — Chuẩn bị Git repo cho lab

ArgoCD cần 1 Git repo thật để theo dõi. Cách đơn giản nhất: tạo 1 repo mới trên GitHub (miễn phí, public hoặc private đều được):

```powershell
cd C:\gitops-cnpg-lab
git init
git add .
git commit -m "Khoi tao lab GitOps CloudNativePG"
git branch -M main
git remote add origin https://github.com/<TEN_GITHUB_CUA_BAN>/gitops-cnpg-lab.git
git push -u origin main
```

### Bước 3.4 — Build image migration đầu tiên (v1) và đẩy lên Docker Hub

```powershell
cd C:\gitops-cnpg-lab
docker build -t <TEN_DOCKERHUB_CUA_BAN>/insurance-db-migrator:v1 -f Dockerfile.migrator .
docker login
docker push <TEN_DOCKERHUB_CUA_BAN>/insurance-db-migrator:v1
```

Sửa file `k8s-manifests/02-migration-job.yaml`, thay đúng tên image bạn vừa push, rồi sửa `k8s-manifests/00-argocd-application.yaml` thay đúng `repoURL` bằng repo GitHub bạn vừa tạo. Commit và push lại:
```powershell
git add .
git commit -m "Cap nhat image migration v1 va repo URL"
git push
```

### Bước 3.5 — Tạo ArgoCD Application để bắt đầu theo dõi Git repo

```powershell
kubectl apply -f C:\gitops-cnpg-lab\k8s-manifests\00-argocd-application.yaml
```

Kiểm tra trạng thái:
```powershell
kubectl get application -n argocd
```
→ Vào lại giao diện ArgoCD (https://localhost:8080), sẽ thấy Application `insurance-db-platform` tự động Sync — ArgoCD áp dụng `01-cnpg-cluster.yaml` (**nhưng cluster đã tồn tại từ Phase 1 nên không tạo lại, ArgoCD chỉ "nhận quản lý" cluster hiện có**), và chạy Job `insurance-db-migrate` để áp dụng migration `v1`.

Xác nhận Job đã chạy và migration đã áp dụng:
```powershell
kubectl get jobs -n insurance-system
kubectl logs -n insurance-system -l job-name=insurance-db-migrate
```
→ Log phải có dòng tương tự `+ create_contracts_table .. ok` (đúng migration đã test ở use case GitOps trước).

### Bước 3.6 — Mô phỏng "developer commit code mới" — thêm 1 schema change

Thêm 1 migration mới vào Sqitch project:
```powershell
cd C:\gitops-cnpg-lab\db-migrations
sqitch add add_notes_column --requires create_contracts_table -n "Them cot notes vao contracts"
```
Sửa file `deploy/add_notes_column.sql` vừa tạo, thêm nội dung:
```sql
BEGIN;
ALTER TABLE app.contracts ADD COLUMN notes TEXT;
COMMIT;
```
Và file `revert/add_notes_column.sql`:
```sql
BEGIN;
ALTER TABLE app.contracts DROP COLUMN notes;
COMMIT;
```

### Bước 3.7 — Build lại image với tag mới (v2), đại diện cho "phiên bản schema mới"

```powershell
cd C:\gitops-cnpg-lab
docker build -t <TEN_DOCKERHUB_CUA_BAN>/insurance-db-migrator:v2 -f Dockerfile.migrator .
docker push <TEN_DOCKERHUB_CUA_BAN>/insurance-db-migrator:v2
```

### Bước 3.8 — Đây chính là "commit code mới lên Git" — cập nhật tag image trong manifest

Sửa `k8s-manifests/02-migration-job.yaml`, đổi dòng:
```yaml
image: <TEN_DOCKERHUB_CUA_BAN>/insurance-db-migrator:v1
```
thành:
```yaml
image: <TEN_DOCKERHUB_CUA_BAN>/insurance-db-migrator:v2
```

Commit và push:
```powershell
git add .
git commit -m "Schema v2: them cot notes vao contracts"
git push
```

### Bước 3.9 — Quan sát ArgoCD TỰ ĐỘNG phát hiện và đồng bộ (đây là khoảnh khắc quan trọng nhất của cả lab)

Mặc định ArgoCD poll Git repo mỗi 3 phút — để thấy kết quả ngay lập tức thay vì chờ, có thể ép đồng bộ thủ công (mô phỏng đúng những gì ArgoCD tự làm định kỳ):
```powershell
kubectl exec -n argocd deploy/argocd-repo-server -- argocd app sync insurance-db-platform
```
Hoặc đơn giản bấm nút **Sync** trên giao diện web ArgoCD.

Xác nhận Job migration mới đã chạy với image `v2`:
```powershell
kubectl get jobs -n insurance-system
kubectl logs -n insurance-system -l job-name=insurance-db-migrate --tail=20
```

Xác nhận cột `notes` đã thật sự xuất hiện trong database — **không ai phải SSH vào server hay gõ tay câu lệnh SQL nào**:
```powershell
kubectl exec -it insurance-db-2 -n insurance-system -- psql -U postgres -d pocdb -c "\d app.contracts"
```
*(Thay `insurance-db-2` bằng đúng tên Pod đang là Primary sau failover ở Phase 2.)*

→ Kết quả đúng phải thấy cột `notes | text` xuất hiện trong danh sách cột — **xác nhận toàn bộ chu trình GitOps: commit Git → ArgoCD tự động → Job tự chạy → schema thật sự thay đổi, hoàn thành**.

---

## Dọn dẹp sau khi lab xong

```powershell
kind delete cluster --name pg-lab
```
Lệnh này xoá sạch toàn bộ cluster Kubernetes ảo, không ảnh hưởng gì tới Docker Desktop hay các container khác.

---

## Tổng kết những gì bạn vừa tự tay kiểm chứng qua 3 Phase

| Phase | Đã chứng minh điều gì |
|---|---|
| 1 | CloudNativePG dựng HA cluster chỉ bằng 1 file YAML, tự động Pod Anti-Affinity qua nhiều node |
| 2 | Failover tự động hoàn toàn — kill thẳng Pod Primary, hệ thống tự phục hồi, dữ liệu không mất, Service tự route lại, ứng dụng không cần đổi connection string |
| 3 | Thay đổi schema chỉ cần commit Git — không ai chạy tay script SQL, đúng vòng lặp GitOps hoàn chỉnh |

## Nếu gặp lỗi khi làm theo

Dán nguyên văn lỗi (kèm bạn đang ở bước nào) cho mình — vì tài liệu này chưa được chạy thử thật trong môi trường của mình như đã nói ở đầu, khả năng cao sẽ có 1-2 chỗ cần điều chỉnh nhỏ theo đúng phiên bản phần mềm bạn đang cài, mình sẽ hỗ trợ debug trực tiếp theo lỗi thật bạn gặp.

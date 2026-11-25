# CampusCrew – EC2 deploy

## Steps

**1. Pull this folder onto your EC2 instance**
```bash
git clone https://github.com/<you>/<repo>.git
# or if not on GitHub:
# scp -i <key>.pem -r campuscrew-ec2 ec2-user@<EC2-IP>:~/campuscrew-ec2
```

**2. Run the setup script**
```bash
cd campuscrew-ec2
chmod +x setup.sh
bash setup.sh
```

**3. Open your browser**
```
http://<your-EC2-public-IP>
```

---

## Files in this folder

| File | What it does |
|------|-------------|
| `index.html` | The entire app (self-contained, no backend needed) |
| `campuscrew.nginx.conf` | nginx server block, dropped into `conf.d/` only |
| `setup.sh` | Installs nginx, copies files, reloads — safe to re-run |

## EC2 security group
Make sure port **80 (HTTP)** is open for inbound traffic (`0.0.0.0/0`).

## If you already have nginx with SSL
The config is added as a new block in `/etc/nginx/conf.d/` and does **not** touch your existing config or certificates. If `nginx -t` fails due to a `server_name` conflict, open `campuscrew.nginx.conf`, change `server_name _;` to a subdomain (e.g. `crew.yourdomain.com`), then re-run `bash setup.sh`.

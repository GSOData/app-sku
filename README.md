# 📦 SKU+ | Sistema de Controle de Validade e Estoque

![Python](https://img.shields.io/badge/Python-3.11+-3776AB?style=for-the-badge&logo=python&logoColor=white)
![Django](https://img.shields.io/badge/Django-4.2-092E20?style=for-the-badge&logo=django&logoColor=white)
![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?style=for-the-badge&logo=flutter&logoColor=white)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-15-4169E1?style=for-the-badge&logo=postgresql&logoColor=white)
![Render](https://img.shields.io/badge/Render-Deploy-46E3B7?style=for-the-badge&logo=render&logoColor=white)

---

## 📋 Sobre o Projeto

**SKU+** é um sistema Full Stack desenvolvido para **controle de estoque e prevenção de perdas por validade**, focado em empresas de revenda de bebidas e alimentos perecíveis.

### 🎯 O Problema
Empresas do setor de bebidas enfrentam um desafio constante: **produtos vencendo no estoque sem aviso prévio**. Isso resulta em:
- 💸 Perdas financeiras com descarte de mercadorias.
- ⚠️ Riscos de disponibilizar ao cliente produtos vencidos.
- 📊 Falta de visibilidade em tempo real.

### 💡 A Solução
O **SKU+** coloca o controle na palma da mão de conferentes e gestores:
- ✅ **Dashboard Visual:** Indicadores de status (🔴 Vencido, 🟠 Crítico, 🟡 Alerta, 🟢 OK).
- ✅ **Ordenação Inteligente:** Prioriza automaticamente os lotes que vencem primeiro.
- ✅ **Acesso Remoto:** Backend na nuvem permitindo acesso via 4G/Wi-Fi de qualquer lugar.

---

## 📱 Screenshots

<div align="center">
  <img src="screenshots/login.jpg" width="200" alt="Tela de Login" style="margin-right: 10px;" />
  <img src="screenshots/home.jpg" width="200" alt="Dashboard" />
</div>

---

## 🛠️ Tecnologias Utilizadas

### Backend (API)
- **Framework:** Django 4.2 + Django REST Framework.
- **Autenticação:** JWT (JSON Web Token) com renovação automática.
- **Banco de Dados:** PostgreSQL (Produção no Render) / SQLite (Dev).
- **Servidor:** Gunicorn + Whitenoise (Arquivos estáticos).

### Mobile (App)
- **Framework:** Flutter (Dart).
- **Arquitetura:** MVC com Services pattern.
- **Conexão:** HTTP Package consumindo API REST JSON.

---

## 🚀 Como Rodar o Projeto

### ☁️ Produção (Online)
O backend encontra-se deployado e ativo no Render:
- **Base URL:** `https://app-sku-api.onrender.com/api/`
- **Admin Panel:** `https://app-sku-api.onrender.com/admin/`

### 💻 Localmente (Desenvolvimento)

**1. Clone o Repositório**
```bash
git clone [https://github.com/GSOData/app-sku.git](https://github.com/GSOData/app-sku.git)
cd app-sku
```

---

## 📦 Deploy e Infraestrutura

O projeto foi configurado para **Deploy Contínuo (CI/CD)** via Render.

**Configurações do Web Service:**
- **Build Command:** `./build.sh` (Script personalizado para instalar deps, coletar estáticos e migrar DB).
- **Start Command:** `gunicorn sku_plus.wsgi:application`.
- **Variáveis de Ambiente:**
    - `PYTHON_VERSION`: 3.11.0
    - `DATABASE_URL`: Conexão externa com PostgreSQL.
    - `DEBUG`: False (Segurança).

---

## 🤝 Contribuindo
1. Faça um Fork do projeto.
2. Crie uma Branch (`git checkout -b feature/NovaFeature`).
3. Realize o Commit (`git commit -m 'Adiciona nova feature'`).
4. Realize o Push (`git push origin feature/NovaFeature`).
5. Abra um Pull Request.

---

## ✍️ Autor

| <img src="https://github.com/GSOData.png" width="100px;" alt=""/> |
|:----------------------------------------------------------------:|
| **Gabriel da Silva Oliveira** |
| Desenvolvedor Full Stack                                         |

[![LinkedIn](https://img.shields.io/badge/LinkedIn-0077B5?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/gabriel-silva-devdata/)
[![GitHub](https://img.shields.io/badge/GitHub-100000?style=for-the-badge&logo=github&logoColor=white)](https://github.com/GSOData)

---

<div align="center">
  Feito com 💙 por Gabriel da Silva Oliveira
</div>
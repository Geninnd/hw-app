from fastapi import FastAPI
import uvicorn

app = FastAPI(title="Infra Challenge App")

@app.get("/")
async def home():
    return {"message": "Hello World - Teste 17/06"}

if __name__ == "__main__":
    uvicorn.run("main:app", host="0.0.0.0", port=8000)

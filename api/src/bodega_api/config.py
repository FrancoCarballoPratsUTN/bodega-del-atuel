from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    database_host: str = "localhost"
    database_port: int = 5432
    database_name: str = "bodega_del_atuel"
    database_user: str = "rol_api_lectura_escritura"
    database_password: str
    database_pool_min_size: int = 1
    database_pool_max_size: int = 10

    model_config = SettingsConfigDict(
        env_file=".env",
        env_prefix="BDA_",
        extra="ignore",
    )

    @property
    def database_conninfo(self) -> str:
        return (
            f"host={self.database_host} port={self.database_port} "
            f"dbname={self.database_name} user={self.database_user} "
            f"password={self.database_password}"
        )


@lru_cache
def get_settings() -> Settings:
    return Settings()

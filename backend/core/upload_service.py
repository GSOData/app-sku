import pandas as pd
from io import BytesIO
from datetime import datetime
import logging
from django.db import transaction

from core.models import SKU, UnidadeNegocio

logger = logging.getLogger(__name__)

def parse_disponivel(disponivel_str, fator_conversao: int) -> int:
    """
    Converte a string "Caixas/Unidades" para Unidades Base com proteção para floats.
    """
    if pd.isna(disponivel_str):
        return 0
    
    # Se o Pandas já leu como número puro (int ou float)
    if isinstance(disponivel_str, (int, float)):
        return int(disponivel_str)
        
    disponivel_str = str(disponivel_str).strip()
    if not disponivel_str:
        return 0
    
    if '/' in disponivel_str:
        partes = disponivel_str.split('/')
        try:
            caixas = int(partes[0].replace('.', ''))
            unidades = int(partes[1])
            return caixas * (fator_conversao or 1) + unidades
        except ValueError:
            return 0
    else:
        try:
            # Primeiro tenta converter direto (Lida com casos como '12.0')
            return int(float(disponivel_str))
        except ValueError:
            # Fallback para string formatada de milhares (ex: '1.234')
            return int(disponivel_str.replace('.', ''))


class UploadFefoService:
    @staticmethod
    @transaction.atomic
    def processar_estoque_fefo(file_020502, file_020304, file_nri, unidade_negocio_id: int):
        """
        Processa os relatórios de estoque usando a lógica FEFO Reverso.
        """
        try:
            unidade = UnidadeNegocio.objects.get(id=unidade_negocio_id)
        except UnidadeNegocio.DoesNotExist:
            raise ValueError("Unidade de negócio não encontrada.")

        # Passo A: Leitura e Preparação
        try:
            df_020502 = UploadFefoService._read_file(file_020502)
            df_020304 = UploadFefoService._read_file(file_020304)
            df_nri = UploadFefoService._read_file(file_nri)
        except Exception as e:
            raise ValueError(f"Erro ao ler os arquivos: {e}")

        # =====================================================================
        # INÍCIO DO FILTRO SALVA-VIDAS (Proteção contra formatações do SAP)
        # =====================================================================
        
        # 1. Limpar espaços fantasmas nos nomes das colunas
        df_020502.columns = df_020502.columns.str.strip()
        df_020304.columns = df_020304.columns.str.strip()
        df_nri.columns = df_nri.columns.str.strip()

        # 2. Busca dinâmica das colunas para evitar falhas se o nome mudar ligeiramente
        col_prod_020502 = next((c for c in df_020502.columns if c.lower() in ['produto', 'material', 'cod']), 'Produto')
        col_cod_020304 = next((c for c in df_020304.columns if c.lower() in ['cod', 'material', 'produto']), 'Cod')
        col_cod_nri = next((c for c in df_nri.columns if c.lower() in ['código produto', 'codigo', 'material']), 'Código Produto')

        # 3. Limpeza Extrema: Remove '.0', remove zeros à esquerda e espaços (ex: "0002538 " -> "2538")
        df_020502['Produto_clean'] = df_020502.get(col_prod_020502, pd.Series()).astype(str).str.replace(r'\.0$', '', regex=True).str.lstrip('0').str.strip()
        df_020304['Cod_clean'] = df_020304.get(col_cod_020304, pd.Series()).astype(str).str.replace(r'\.0$', '', regex=True).str.lstrip('0').str.strip()
        df_nri['Codigo_clean'] = df_nri.get(col_cod_nri, pd.Series()).astype(str).str.replace(r'\.0$', '', regex=True).str.lstrip('0').str.strip()
        
        # =====================================================================
        # FIM DO FILTRO SALVA-VIDAS
        # =====================================================================

        # Tratar o NRI
        if 'Data Validade' in df_nri.columns:
            df_nri['Data Validade'] = pd.to_datetime(df_nri['Data Validade'], dayfirst=True, errors='coerce')
        if 'Quantidade' in df_nri.columns:
            df_nri['Quantidade'] = pd.to_numeric(df_nri['Quantidade'], errors='coerce').fillna(0)

        # Obter todos os SKUs da unidade de negócio para rápido acesso
        skus_dict = {
            sku.codigo_sku: sku
            for sku in SKU.objects.filter(unidade_negocio=unidade, ativo=True)
        }
        
        skus_to_update = []

        # Usar df_020502 como fonte de verdade para o que existe de SKU agora
        for idx, row_020502 in df_020502.iterrows():
            cod_sku = row_020502.get('Produto_clean')
            if not cod_sku or pd.isna(cod_sku) or cod_sku.lower() == 'nan':
                continue

            sku = skus_dict.get(cod_sku)
            if not sku:
                continue

            # Passo B: Matemática Gerencial
            str_disponivel = row_020502.get('Disponivel', '0/0')
            qtd_total = parse_disponivel(str_disponivel, sku.fator_conversao)

            # Buscar quantidade no 020304
            row_020304 = df_020304[df_020304['Cod_clean'] == cod_sku]
            qtd_buffer = 0
            if not row_020304.empty:
                col_saida = 'Saidas' if 'Saidas' in row_020304.columns else ('Saída' if 'Saída' in row_020304.columns else None)
                if col_saida:
                    qtd_buffer = pd.to_numeric(row_020304[col_saida], errors='coerce').fillna(0).sum()
                    qtd_buffer = int(qtd_buffer)

            qtd_disponivel = qtd_total - qtd_buffer
            
            # Se não há estoque disponível, zera as datas
            if qtd_disponivel <= 0:
                sku.qtd_total_020502 = qtd_total
                sku.qtd_buffer_020304 = qtd_buffer
                sku.qtd_disponivel_venda = 0
                sku.validade_inicio_range = None
                sku.validade_fim_range = None
                skus_to_update.append(sku)
                continue

            # Passo C: Motor FEFO Reverso
            df_nri_item = df_nri[(df_nri['Codigo_clean'] == cod_sku) & (df_nri['Data Validade'].notna())]
            df_nri_item = df_nri_item.sort_values(by='Data Validade', ascending=True)

            validade_inicio = None
            validade_fim = None

            if not df_nri_item.empty:
                sum_nri = df_nri_item['Quantidade'].sum()
                qtd_queimada = sum_nri - qtd_disponivel

                if qtd_queimada < 0:
                    validade_inicio = df_nri_item.iloc[0]['Data Validade'].date()
                    validade_fim = df_nri_item.iloc[-1]['Data Validade'].date()
                else:
                    for _, row_nri in df_nri_item.iterrows():
                        qtd_linha = row_nri['Quantidade']
                        qtd_queimada -= qtd_linha
                        
                        if qtd_queimada < 0 and validade_inicio is None:
                            validade_inicio = row_nri['Data Validade'].date()
                            
                    if validade_inicio is not None:
                        validade_fim = df_nri_item.iloc[-1]['Data Validade'].date()
            
            # Passo D: Atualização no banco
            sku.qtd_total_020502 = qtd_total
            sku.qtd_buffer_020304 = qtd_buffer
            sku.qtd_disponivel_venda = qtd_disponivel
            sku.validade_inicio_range = validade_inicio
            sku.validade_fim_range = validade_fim
            skus_to_update.append(sku)

        if skus_to_update:
            SKU.objects.bulk_update(
                skus_to_update, 
                ['qtd_total_020502', 'qtd_buffer_020304', 'qtd_disponivel_venda', 'validade_inicio_range', 'validade_fim_range']
            )

        return {
            'success': True,
            'skus_atualizados': len(skus_to_update)
        }

    @staticmethod
    def _read_file(file) -> pd.DataFrame:
        filename = file.name.lower()
        if filename.endswith('.csv'):
            for encoding in ['utf-8', 'latin-1', 'cp1252']:
                for sep in [';', ',', '\t', '|']:
                    try:
                        file.seek(0)
                        df = pd.read_csv(file, encoding=encoding, sep=sep)
                        if len(df.columns) > 1:
                            return df
                    except Exception:
                        continue
            raise ValueError(f"Não foi possível processar o CSV: {filename}. Verifique a formatação.")
        else:
            file.seek(0)
            return pd.read_excel(file)
// lib/nutricion/menus/nutricion_menus_screen.dart

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:todo/services/nutricion_service.dart';
import 'package:todo/nutricion/ingredientes/nutricion_ingredientes_screen.dart';
import 'package:todo/theme/app_typography.dart';
import '../widgets/nutrition_shared_widgets.dart';

const List<String> kTiemposComida = ['Desayuno', 'Almuerzo', 'Cena', 'Refrigerio'];

const Map<String, IconData> kIconosTiempo = {
  'Desayuno': Icons.wb_sunny_outlined,
  'Almuerzo': Icons.lunch_dining_outlined,
  'Cena': Icons.nightlight_outlined,
  'Refrigerio': Icons.apple_outlined,
};

const Map<String, Color> kColorTiempo = {
  'Desayuno': Color(0xFF92400E),
  'Almuerzo': Color(0xFF166534),
  'Cena': Color(0xFF1E40AF),
  'Refrigerio': Color(0xFF9D174D),
};

// ---------------------------------------------------------------------------
// Plantillas base de dietas institucionales (20 tipos clínicos)
// Fuente: Especificaciones de Dieta institucional USPEC/Capital.
// Cada plantilla es un punto de partida; el nutricionista la personaliza.
// Ingredientes tomados del catálogo kIngredientesBase (TBL_INGREDIENTES).
// ---------------------------------------------------------------------------
const List<Map<String, dynamic>> kDietasDefault = [
  // ── 1. Normal ─────────────────────────────────────────────────────────────
  {
    'nombre': 'Dieta Normal',
    'descripcion': 'Alimentación equilibrada estándar sin restricciones.',
    'tiempos': {
      'Desayuno': [
        {'nombre': 'Pan', 'gramos': '1', 'unidad': 'und'},
        {'nombre': 'Huevo', 'gramos': '1', 'unidad': 'und'},
        {'nombre': 'Queso', 'gramos': '35', 'unidad': 'g'},
        {'nombre': 'Fruta de mano (entera)', 'gramos': '1', 'unidad': 'und'},
        {'nombre': 'Aromática / infusión', 'gramos': '200', 'unidad': 'ml'},
      ],
      'Almuerzo': [
        {'nombre': 'Arroz cocido', 'gramos': '170', 'unidad': 'g'},
        {'nombre': 'Pechuga sin hueso cocida', 'gramos': '78', 'unidad': 'g'},
        {'nombre': 'Tubérculo (papa/yuca/plátano)', 'gramos': '80', 'unidad': 'g'},
        {'nombre': 'Ensalada mixta', 'gramos': '100', 'unidad': 'g'},
        {'nombre': 'Agua', 'gramos': '250', 'unidad': 'ml'},
      ],
      'Cena': [
        {'nombre': 'Arroz cocido', 'gramos': '170', 'unidad': 'g'},
        {'nombre': 'Pechuga sin hueso cocida', 'gramos': '78', 'unidad': 'g'},
        {'nombre': 'Tubérculo (papa/yuca/plátano)', 'gramos': '80', 'unidad': 'g'},
        {'nombre': 'Agua', 'gramos': '250', 'unidad': 'ml'},
      ],
      'Refrigerio': [
        {'nombre': 'Pan', 'gramos': '1', 'unidad': 'und'},
        {'nombre': 'Fruta de mano (entera)', 'gramos': '1', 'unidad': 'und'},
      ],
    },
  },
  // ── 2. Líquida Clara ──────────────────────────────────────────────────────
  {
    'nombre': 'Líquida Clara',
    'descripcion': 'Solo líquidos transparentes. Post-cirugía o pre-procedimientos diagnósticos.',
    'tiempos': {
      'Desayuno': [
        {'nombre': 'Agua', 'gramos': '250', 'unidad': 'ml'},
        {'nombre': 'Aromática / infusión', 'gramos': '200', 'unidad': 'ml'},
      ],
      'Almuerzo': [
        {'nombre': 'Agua', 'gramos': '250', 'unidad': 'ml'},
        {'nombre': 'Aromática / infusión', 'gramos': '200', 'unidad': 'ml'},
      ],
      'Cena': [
        {'nombre': 'Agua', 'gramos': '250', 'unidad': 'ml'},
        {'nombre': 'Aromática / infusión', 'gramos': '200', 'unidad': 'ml'},
      ],
      'Refrigerio': [
        {'nombre': 'Agua', 'gramos': '250', 'unidad': 'ml'},
      ],
    },
  },
  // ── 3. Líquida Completa ───────────────────────────────────────────────────
  {
    'nombre': 'Líquida Completa',
    'descripcion': 'Líquidos con mayor valor nutricional. Transición hacia dieta blanda.',
    'tiempos': {
      'Desayuno': [
        {'nombre': 'Leche entera', 'gramos': '200', 'unidad': 'ml'},
        {'nombre': 'Aromática / infusión', 'gramos': '200', 'unidad': 'ml'},
      ],
      'Almuerzo': [
        {'nombre': 'Jugo natural', 'gramos': '200', 'unidad': 'ml'},
        {'nombre': 'Agua', 'gramos': '250', 'unidad': 'ml'},
      ],
      'Cena': [
        {'nombre': 'Leche entera', 'gramos': '200', 'unidad': 'ml'},
        {'nombre': 'Agua', 'gramos': '250', 'unidad': 'ml'},
      ],
      'Refrigerio': [
        {'nombre': 'Yogur', 'gramos': '100', 'unidad': 'g'},
      ],
    },
  },
  // ── 4. Blanda ─────────────────────────────────────────────────────────────
  {
    'nombre': 'Blanda',
    'descripcion': 'Textura suave, fácil digestión. Post-quirúrgica o problemas gastrointestinales.',
    'tiempos': {
      'Desayuno': [
        {'nombre': 'Avena', 'gramos': '40', 'unidad': 'g'},
        {'nombre': 'Leche entera', 'gramos': '200', 'unidad': 'ml'},
        {'nombre': 'Fruta porcionada', 'gramos': '80', 'unidad': 'g'},
      ],
      'Almuerzo': [
        {'nombre': 'Arroz cocido', 'gramos': '170', 'unidad': 'g'},
        {'nombre': 'Pechuga sin hueso cocida', 'gramos': '78', 'unidad': 'g'},
        {'nombre': 'Papa cocida', 'gramos': '120', 'unidad': 'g'},
        {'nombre': 'Agua', 'gramos': '250', 'unidad': 'ml'},
      ],
      'Cena': [
        {'nombre': 'Arroz cocido', 'gramos': '170', 'unidad': 'g'},
        {'nombre': 'Huevo', 'gramos': '1', 'unidad': 'und'},
        {'nombre': 'Papa cocida', 'gramos': '120', 'unidad': 'g'},
        {'nombre': 'Agua', 'gramos': '250', 'unidad': 'ml'},
      ],
      'Refrigerio': [
        {'nombre': 'Yogur', 'gramos': '100', 'unidad': 'g'},
        {'nombre': 'Galleta', 'gramos': '3', 'unidad': 'und'},
      ],
    },
  },
  // ── 5. Hipocalórica ───────────────────────────────────────────────────────
  {
    'nombre': 'Hipocalórica',
    'descripcion': 'Reducida en calorías. Control de sobrepeso u obesidad.',
    'tiempos': {
      'Desayuno': [
        {'nombre': 'Pan', 'gramos': '1', 'unidad': 'und'},
        {'nombre': 'Huevo', 'gramos': '1', 'unidad': 'und'},
        {'nombre': 'Fruta de mano (entera)', 'gramos': '1', 'unidad': 'und'},
        {'nombre': 'Aromática / infusión', 'gramos': '200', 'unidad': 'ml'},
      ],
      'Almuerzo': [
        {'nombre': 'Arroz cocido (HPP/HPC)', 'gramos': '85', 'unidad': 'g'},
        {'nombre': 'Pechuga sin hueso cocida (HPP/HPC)', 'gramos': '39', 'unidad': 'g'},
        {'nombre': 'Ensalada mixta', 'gramos': '100', 'unidad': 'g'},
        {'nombre': 'Verduras al vapor', 'gramos': '100', 'unidad': 'g'},
        {'nombre': 'Agua', 'gramos': '250', 'unidad': 'ml'},
      ],
      'Cena': [
        {'nombre': 'Arroz cocido (HPP/HPC)', 'gramos': '85', 'unidad': 'g'},
        {'nombre': 'Pechuga sin hueso cocida (HPP/HPC)', 'gramos': '39', 'unidad': 'g'},
        {'nombre': 'Ensalada mixta', 'gramos': '100', 'unidad': 'g'},
        {'nombre': 'Agua', 'gramos': '250', 'unidad': 'ml'},
      ],
      'Refrigerio': [
        {'nombre': 'Fruta de mano (entera)', 'gramos': '1', 'unidad': 'und'},
        {'nombre': 'Agua', 'gramos': '250', 'unidad': 'ml'},
      ],
    },
  },
  // ── 6. Hipograsa ──────────────────────────────────────────────────────────
  {
    'nombre': 'Hipograsa',
    'descripcion': 'Baja en grasas. Afecciones hepáticas, biliares o cardiovasculares.',
    'tiempos': {
      'Desayuno': [
        {'nombre': 'Pan', 'gramos': '1', 'unidad': 'und'},
        {'nombre': 'Huevo', 'gramos': '1', 'unidad': 'und'},
        {'nombre': 'Fruta de mano (entera)', 'gramos': '1', 'unidad': 'und'},
        {'nombre': 'Aromática / infusión', 'gramos': '200', 'unidad': 'ml'},
      ],
      'Almuerzo': [
        {'nombre': 'Arroz cocido', 'gramos': '170', 'unidad': 'g'},
        {'nombre': 'Pechuga sin hueso cocida', 'gramos': '78', 'unidad': 'g'},
        {'nombre': 'Ensalada mixta', 'gramos': '100', 'unidad': 'g'},
        {'nombre': 'Agua', 'gramos': '250', 'unidad': 'ml'},
      ],
      'Cena': [
        {'nombre': 'Arroz cocido', 'gramos': '170', 'unidad': 'g'},
        {'nombre': 'Pescado', 'gramos': '1', 'unidad': 'und'},
        {'nombre': 'Verduras al vapor', 'gramos': '100', 'unidad': 'g'},
        {'nombre': 'Agua', 'gramos': '250', 'unidad': 'ml'},
      ],
      'Refrigerio': [
        {'nombre': 'Fruta de mano (entera)', 'gramos': '1', 'unidad': 'und'},
        {'nombre': 'Agua', 'gramos': '250', 'unidad': 'ml'},
      ],
    },
  },
  // ── 7. Hipercalórica ──────────────────────────────────────────────────────
  {
    'nombre': 'Hipercalórica',
    'descripcion': 'Alto valor energético. Desnutrición, caquexia o recuperación nutricional.',
    'tiempos': {
      'Desayuno': [
        {'nombre': 'Avena', 'gramos': '40', 'unidad': 'g'},
        {'nombre': 'Leche entera', 'gramos': '200', 'unidad': 'ml'},
        {'nombre': 'Pan', 'gramos': '1', 'unidad': 'und'},
        {'nombre': 'Huevo', 'gramos': '1', 'unidad': 'und'},
        {'nombre': 'Fruta de mano (entera)', 'gramos': '1', 'unidad': 'und'},
      ],
      'Almuerzo': [
        {'nombre': 'Arroz cocido', 'gramos': '170', 'unidad': 'g'},
        {'nombre': 'Carne de res cocida', 'gramos': '78', 'unidad': 'g'},
        {'nombre': 'Tubérculo (papa/yuca/plátano)', 'gramos': '80', 'unidad': 'g'},
        {'nombre': 'Aguacate', 'gramos': '60', 'unidad': 'g'},
        {'nombre': 'Ensalada mixta', 'gramos': '100', 'unidad': 'g'},
        {'nombre': 'Agua', 'gramos': '250', 'unidad': 'ml'},
      ],
      'Cena': [
        {'nombre': 'Arroz cocido', 'gramos': '170', 'unidad': 'g'},
        {'nombre': 'Pechuga sin hueso cocida', 'gramos': '78', 'unidad': 'g'},
        {'nombre': 'Tubérculo (papa/yuca/plátano)', 'gramos': '80', 'unidad': 'g'},
        {'nombre': 'Agua', 'gramos': '250', 'unidad': 'ml'},
      ],
      'Refrigerio': [
        {'nombre': 'Pan', 'gramos': '1', 'unidad': 'und'},
        {'nombre': 'Maní / Nueces', 'gramos': '30', 'unidad': 'g'},
        {'nombre': 'Banano', 'gramos': '1', 'unidad': 'und'},
      ],
    },
  },
  // ── 8. Hiperproteica ──────────────────────────────────────────────────────
  {
    'nombre': 'Hiperproteica',
    'descripcion': 'Alta en proteínas. Recuperación muscular, heridas, cirugías, catabolismo.',
    'tiempos': {
      'Desayuno': [
        {'nombre': 'Huevo', 'gramos': '1', 'unidad': 'und'},
        {'nombre': 'Queso', 'gramos': '35', 'unidad': 'g'},
        {'nombre': 'Pan', 'gramos': '1', 'unidad': 'und'},
        {'nombre': 'Leche entera', 'gramos': '200', 'unidad': 'ml'},
      ],
      'Almuerzo': [
        {'nombre': 'Arroz cocido', 'gramos': '170', 'unidad': 'g'},
        {'nombre': 'Pechuga sin hueso cocida', 'gramos': '78', 'unidad': 'g'},
        {'nombre': 'Huevo', 'gramos': '1', 'unidad': 'und'},
        {'nombre': 'Fríjoles / Lentejas cocidos', 'gramos': '60', 'unidad': 'g'},
        {'nombre': 'Agua', 'gramos': '250', 'unidad': 'ml'},
      ],
      'Cena': [
        {'nombre': 'Arroz cocido', 'gramos': '170', 'unidad': 'g'},
        {'nombre': 'Pescado', 'gramos': '1', 'unidad': 'und'},
        {'nombre': 'Queso (HPP/HPC)', 'gramos': '17.5', 'unidad': 'g'},
        {'nombre': 'Agua', 'gramos': '250', 'unidad': 'ml'},
      ],
      'Refrigerio': [
        {'nombre': 'Huevo', 'gramos': '1', 'unidad': 'und'},
        {'nombre': 'Fruta de mano (entera)', 'gramos': '1', 'unidad': 'und'},
      ],
    },
  },
  // ── 9. Hipoglucida ────────────────────────────────────────────────────────
  {
    'nombre': 'Hipoglucida',
    'descripcion': 'Baja en carbohidratos. Control glucémico, diabetes, resistencia a la insulina.',
    'tiempos': {
      'Desayuno': [
        {'nombre': 'Huevo', 'gramos': '1', 'unidad': 'und'},
        {'nombre': 'Queso', 'gramos': '35', 'unidad': 'g'},
        {'nombre': 'Fruta porcionada', 'gramos': '80', 'unidad': 'g'},
        {'nombre': 'Aromática / infusión', 'gramos': '200', 'unidad': 'ml'},
      ],
      'Almuerzo': [
        {'nombre': 'Tubérculo HPP/HPC', 'gramos': '80', 'unidad': 'g'},
        {'nombre': 'Carne de res cocida', 'gramos': '78', 'unidad': 'g'},
        {'nombre': 'Ensalada mixta', 'gramos': '100', 'unidad': 'g'},
        {'nombre': 'Verduras al vapor', 'gramos': '100', 'unidad': 'g'},
        {'nombre': 'Agua', 'gramos': '250', 'unidad': 'ml'},
      ],
      'Cena': [
        {'nombre': 'Pechuga sin hueso cocida', 'gramos': '78', 'unidad': 'g'},
        {'nombre': 'Huevo', 'gramos': '1', 'unidad': 'und'},
        {'nombre': 'Verduras al vapor', 'gramos': '100', 'unidad': 'g'},
        {'nombre': 'Agua', 'gramos': '250', 'unidad': 'ml'},
      ],
      'Refrigerio': [
        {'nombre': 'Maní / Nueces', 'gramos': '30', 'unidad': 'g'},
        {'nombre': 'Agua', 'gramos': '250', 'unidad': 'ml'},
      ],
    },
  },
  // ── 10. Hiposódica ────────────────────────────────────────────────────────
  {
    'nombre': 'Hiposódica',
    'descripcion': 'Baja en sodio. Hipertensión arterial, retención de líquidos, insuficiencia cardíaca.',
    'tiempos': {
      'Desayuno': [
        {'nombre': 'Avena', 'gramos': '40', 'unidad': 'g'},
        {'nombre': 'Fruta de mano (entera)', 'gramos': '1', 'unidad': 'und'},
        {'nombre': 'Aromática / infusión', 'gramos': '200', 'unidad': 'ml'},
      ],
      'Almuerzo': [
        {'nombre': 'Arroz cocido', 'gramos': '170', 'unidad': 'g'},
        {'nombre': 'Pechuga sin hueso cocida', 'gramos': '78', 'unidad': 'g'},
        {'nombre': 'Verduras al vapor', 'gramos': '100', 'unidad': 'g'},
        {'nombre': 'Agua', 'gramos': '250', 'unidad': 'ml'},
      ],
      'Cena': [
        {'nombre': 'Arroz cocido', 'gramos': '170', 'unidad': 'g'},
        {'nombre': 'Pescado', 'gramos': '1', 'unidad': 'und'},
        {'nombre': 'Ensalada mixta', 'gramos': '100', 'unidad': 'g'},
        {'nombre': 'Agua', 'gramos': '250', 'unidad': 'ml'},
      ],
      'Refrigerio': [
        {'nombre': 'Fruta de mano (entera)', 'gramos': '1', 'unidad': 'und'},
        {'nombre': 'Agua', 'gramos': '250', 'unidad': 'ml'},
      ],
    },
  },
  // ── 11. Alta en Hierro ────────────────────────────────────────────────────
  {
    'nombre': 'Alta en Hierro',
    'descripcion': 'Rica en hierro. Anemia ferropénica o deficiencia de hierro.',
    'tiempos': {
      'Desayuno': [
        {'nombre': 'Pan', 'gramos': '1', 'unidad': 'und'},
        {'nombre': 'Huevo', 'gramos': '1', 'unidad': 'und'},
        {'nombre': 'Naranja', 'gramos': '1', 'unidad': 'und'},
        {'nombre': 'Aromática / infusión', 'gramos': '200', 'unidad': 'ml'},
      ],
      'Almuerzo': [
        {'nombre': 'Arroz cocido', 'gramos': '170', 'unidad': 'g'},
        {'nombre': 'Carne de res cocida', 'gramos': '78', 'unidad': 'g'},
        {'nombre': 'Fríjoles / Lentejas cocidos', 'gramos': '60', 'unidad': 'g'},
        {'nombre': 'Ensalada mixta', 'gramos': '100', 'unidad': 'g'},
        {'nombre': 'Agua', 'gramos': '250', 'unidad': 'ml'},
      ],
      'Cena': [
        {'nombre': 'Arroz cocido', 'gramos': '170', 'unidad': 'g'},
        {'nombre': 'Carne de res cocida', 'gramos': '78', 'unidad': 'g'},
        {'nombre': 'Tubérculo (papa/yuca/plátano)', 'gramos': '80', 'unidad': 'g'},
        {'nombre': 'Agua', 'gramos': '250', 'unidad': 'ml'},
      ],
      'Refrigerio': [
        {'nombre': 'Fruta porcionada', 'gramos': '80', 'unidad': 'g'},
        {'nombre': 'Agua', 'gramos': '250', 'unidad': 'ml'},
      ],
    },
  },
  // ── 12. Astringente ───────────────────────────────────────────────────────
  {
    'nombre': 'Astringente',
    'descripcion': 'Reduce el tránsito intestinal. Diarrea aguda o síndrome de intestino irritable.',
    'tiempos': {
      'Desayuno': [
        {'nombre': 'Arroz cocido', 'gramos': '170', 'unidad': 'g'},
        {'nombre': 'Galleta', 'gramos': '3', 'unidad': 'und'},
        {'nombre': 'Manzana', 'gramos': '1', 'unidad': 'und'},
        {'nombre': 'Agua', 'gramos': '250', 'unidad': 'ml'},
      ],
      'Almuerzo': [
        {'nombre': 'Arroz cocido', 'gramos': '170', 'unidad': 'g'},
        {'nombre': 'Pechuga sin hueso cocida', 'gramos': '78', 'unidad': 'g'},
        {'nombre': 'Zanahoria', 'gramos': '50', 'unidad': 'g'},
        {'nombre': 'Papa cocida', 'gramos': '120', 'unidad': 'g'},
        {'nombre': 'Agua', 'gramos': '250', 'unidad': 'ml'},
      ],
      'Cena': [
        {'nombre': 'Arroz cocido', 'gramos': '170', 'unidad': 'g'},
        {'nombre': 'Pollo (presa entera)', 'gramos': '1', 'unidad': 'und'},
        {'nombre': 'Papa cocida', 'gramos': '120', 'unidad': 'g'},
        {'nombre': 'Agua', 'gramos': '250', 'unidad': 'ml'},
      ],
      'Refrigerio': [
        {'nombre': 'Galleta', 'gramos': '3', 'unidad': 'und'},
        {'nombre': 'Manzana', 'gramos': '1', 'unidad': 'und'},
        {'nombre': 'Agua', 'gramos': '250', 'unidad': 'ml'},
      ],
    },
  },
  // ── 13. Alta en Fibra ─────────────────────────────────────────────────────
  {
    'nombre': 'Alta en Fibra',
    'descripcion': 'Rica en fibra dietética. Estreñimiento crónico, síndrome metabólico.',
    'tiempos': {
      'Desayuno': [
        {'nombre': 'Avena', 'gramos': '40', 'unidad': 'g'},
        {'nombre': 'Fruta de mano (entera)', 'gramos': '1', 'unidad': 'und'},
        {'nombre': 'Aromática / infusión', 'gramos': '200', 'unidad': 'ml'},
      ],
      'Almuerzo': [
        {'nombre': 'Arroz cocido', 'gramos': '170', 'unidad': 'g'},
        {'nombre': 'Pechuga sin hueso cocida', 'gramos': '78', 'unidad': 'g'},
        {'nombre': 'Fríjoles / Lentejas cocidos', 'gramos': '60', 'unidad': 'g'},
        {'nombre': 'Ensalada mixta', 'gramos': '100', 'unidad': 'g'},
        {'nombre': 'Agua', 'gramos': '250', 'unidad': 'ml'},
      ],
      'Cena': [
        {'nombre': 'Arroz cocido', 'gramos': '170', 'unidad': 'g'},
        {'nombre': 'Carne de res cocida', 'gramos': '78', 'unidad': 'g'},
        {'nombre': 'Verduras al vapor', 'gramos': '100', 'unidad': 'g'},
        {'nombre': 'Agua', 'gramos': '250', 'unidad': 'ml'},
      ],
      'Refrigerio': [
        {'nombre': 'Fruta de mano (entera)', 'gramos': '1', 'unidad': 'und'},
        {'nombre': 'Maní / Nueces', 'gramos': '30', 'unidad': 'g'},
      ],
    },
  },
  // ── 14. Renal ─────────────────────────────────────────────────────────────
  {
    'nombre': 'Renal',
    'descripcion': 'Restricción de proteína, Na, K y P. Insuficiencia renal crónica.',
    'tiempos': {
      'Desayuno': [
        {'nombre': 'Pan', 'gramos': '1', 'unidad': 'und'},
        {'nombre': 'Huevo', 'gramos': '1', 'unidad': 'und'},
        {'nombre': 'Fruta porcionada', 'gramos': '80', 'unidad': 'g'},
        {'nombre': 'Agua', 'gramos': '250', 'unidad': 'ml'},
      ],
      'Almuerzo': [
        {'nombre': 'Arroz cocido (HPP/HPC)', 'gramos': '85', 'unidad': 'g'},
        {'nombre': 'Pechuga sin hueso cocida (HPP/HPC)', 'gramos': '39', 'unidad': 'g'},
        {'nombre': 'Ensalada mixta', 'gramos': '100', 'unidad': 'g'},
        {'nombre': 'Agua', 'gramos': '250', 'unidad': 'ml'},
      ],
      'Cena': [
        {'nombre': 'Arroz cocido (HPP/HPC)', 'gramos': '85', 'unidad': 'g'},
        {'nombre': 'Pechuga sin hueso cocida (HPP/HPC)', 'gramos': '39', 'unidad': 'g'},
        {'nombre': 'Verduras al vapor', 'gramos': '100', 'unidad': 'g'},
        {'nombre': 'Agua', 'gramos': '250', 'unidad': 'ml'},
      ],
      'Refrigerio': [
        {'nombre': 'Fruta porcionada', 'gramos': '80', 'unidad': 'g'},
        {'nombre': 'Agua', 'gramos': '250', 'unidad': 'ml'},
      ],
    },
  },
  // ── 15. Hipopurínica ──────────────────────────────────────────────────────
  {
    'nombre': 'Hipopurínica',
    'descripcion': 'Baja en purinas. Gota e hiperuricemia. Excluir vísceras y carnes rojas.',
    'tiempos': {
      'Desayuno': [
        {'nombre': 'Pan', 'gramos': '1', 'unidad': 'und'},
        {'nombre': 'Huevo', 'gramos': '1', 'unidad': 'und'},
        {'nombre': 'Leche entera', 'gramos': '200', 'unidad': 'ml'},
        {'nombre': 'Fruta de mano (entera)', 'gramos': '1', 'unidad': 'und'},
      ],
      'Almuerzo': [
        {'nombre': 'Arroz cocido', 'gramos': '170', 'unidad': 'g'},
        {'nombre': 'Pechuga sin hueso cocida', 'gramos': '78', 'unidad': 'g'},
        {'nombre': 'Tubérculo (papa/yuca/plátano)', 'gramos': '80', 'unidad': 'g'},
        {'nombre': 'Ensalada mixta', 'gramos': '100', 'unidad': 'g'},
        {'nombre': 'Agua', 'gramos': '250', 'unidad': 'ml'},
      ],
      'Cena': [
        {'nombre': 'Arroz cocido', 'gramos': '170', 'unidad': 'g'},
        {'nombre': 'Huevo', 'gramos': '1', 'unidad': 'und'},
        {'nombre': 'Queso', 'gramos': '35', 'unidad': 'g'},
        {'nombre': 'Verduras al vapor', 'gramos': '100', 'unidad': 'g'},
        {'nombre': 'Agua', 'gramos': '250', 'unidad': 'ml'},
      ],
      'Refrigerio': [
        {'nombre': 'Yogur', 'gramos': '100', 'unidad': 'g'},
        {'nombre': 'Fruta de mano (entera)', 'gramos': '1', 'unidad': 'und'},
      ],
    },
  },
  // ── 16. Sin Irritantes Gástricos ─────────────────────────────────────────
  {
    'nombre': 'Sin Irritantes Gástricos',
    'descripcion': 'Excluye condimentos, cafeína y ácidos. Gastritis, úlcera péptica.',
    'tiempos': {
      'Desayuno': [
        {'nombre': 'Avena', 'gramos': '40', 'unidad': 'g'},
        {'nombre': 'Leche entera', 'gramos': '200', 'unidad': 'ml'},
        {'nombre': 'Pan', 'gramos': '1', 'unidad': 'und'},
        {'nombre': 'Aromática / infusión', 'gramos': '200', 'unidad': 'ml'},
      ],
      'Almuerzo': [
        {'nombre': 'Arroz cocido', 'gramos': '170', 'unidad': 'g'},
        {'nombre': 'Pechuga sin hueso cocida', 'gramos': '78', 'unidad': 'g'},
        {'nombre': 'Papa cocida', 'gramos': '120', 'unidad': 'g'},
        {'nombre': 'Verduras al vapor', 'gramos': '100', 'unidad': 'g'},
        {'nombre': 'Agua', 'gramos': '250', 'unidad': 'ml'},
      ],
      'Cena': [
        {'nombre': 'Arroz cocido', 'gramos': '170', 'unidad': 'g'},
        {'nombre': 'Pescado', 'gramos': '1', 'unidad': 'und'},
        {'nombre': 'Papa cocida', 'gramos': '120', 'unidad': 'g'},
        {'nombre': 'Agua', 'gramos': '250', 'unidad': 'ml'},
      ],
      'Refrigerio': [
        {'nombre': 'Galleta', 'gramos': '3', 'unidad': 'und'},
        {'nombre': 'Agua', 'gramos': '250', 'unidad': 'ml'},
      ],
    },
  },
  // ── 17. Libre de Lactosa ──────────────────────────────────────────────────
  {
    'nombre': 'Libre de Lactosa',
    'descripcion': 'Exclusión total de lactosa. Intolerancia a la lactosa confirmada.',
    'tiempos': {
      'Desayuno': [
        {'nombre': 'Pan', 'gramos': '1', 'unidad': 'und'},
        {'nombre': 'Huevo', 'gramos': '1', 'unidad': 'und'},
        {'nombre': 'Fruta de mano (entera)', 'gramos': '1', 'unidad': 'und'},
        {'nombre': 'Agua', 'gramos': '250', 'unidad': 'ml'},
      ],
      'Almuerzo': [
        {'nombre': 'Arroz cocido', 'gramos': '170', 'unidad': 'g'},
        {'nombre': 'Pechuga sin hueso cocida', 'gramos': '78', 'unidad': 'g'},
        {'nombre': 'Tubérculo (papa/yuca/plátano)', 'gramos': '80', 'unidad': 'g'},
        {'nombre': 'Ensalada mixta', 'gramos': '100', 'unidad': 'g'},
        {'nombre': 'Agua', 'gramos': '250', 'unidad': 'ml'},
      ],
      'Cena': [
        {'nombre': 'Arroz cocido', 'gramos': '170', 'unidad': 'g'},
        {'nombre': 'Carne de res cocida', 'gramos': '78', 'unidad': 'g'},
        {'nombre': 'Tubérculo (papa/yuca/plátano)', 'gramos': '80', 'unidad': 'g'},
        {'nombre': 'Agua', 'gramos': '250', 'unidad': 'ml'},
      ],
      'Refrigerio': [
        {'nombre': 'Fruta de mano (entera)', 'gramos': '1', 'unidad': 'und'},
        {'nombre': 'Agua', 'gramos': '250', 'unidad': 'ml'},
      ],
    },
  },
  // ── 18. Reflujo Esofágico ─────────────────────────────────────────────────
  {
    'nombre': 'Reflujo Esofágico',
    'descripcion': 'Fraccionada, baja en grasa y acidez. ERGE / reflujo gastroesofágico.',
    'tiempos': {
      'Desayuno': [
        {'nombre': 'Pan', 'gramos': '1', 'unidad': 'und'},
        {'nombre': 'Huevo', 'gramos': '1', 'unidad': 'und'},
        {'nombre': 'Fruta porcionada', 'gramos': '80', 'unidad': 'g'},
        {'nombre': 'Agua', 'gramos': '250', 'unidad': 'ml'},
      ],
      'Almuerzo': [
        {'nombre': 'Arroz cocido (HPP/HPC)', 'gramos': '85', 'unidad': 'g'},
        {'nombre': 'Pechuga sin hueso cocida (HPP/HPC)', 'gramos': '39', 'unidad': 'g'},
        {'nombre': 'Verduras al vapor', 'gramos': '100', 'unidad': 'g'},
        {'nombre': 'Agua', 'gramos': '250', 'unidad': 'ml'},
      ],
      'Cena': [
        {'nombre': 'Arroz cocido (HPP/HPC)', 'gramos': '85', 'unidad': 'g'},
        {'nombre': 'Pechuga sin hueso cocida (HPP/HPC)', 'gramos': '39', 'unidad': 'g'},
        {'nombre': 'Papa cocida', 'gramos': '120', 'unidad': 'g'},
        {'nombre': 'Agua', 'gramos': '250', 'unidad': 'ml'},
      ],
      'Refrigerio': [
        {'nombre': 'Galleta', 'gramos': '3', 'unidad': 'und'},
        {'nombre': 'Agua', 'gramos': '250', 'unidad': 'ml'},
      ],
    },
  },
  // ── 19. Vegetariana ───────────────────────────────────────────────────────
  {
    'nombre': 'Vegetariana',
    'descripcion': 'Sin carnes. Por elección, creencias o indicación médica.',
    'tiempos': {
      'Desayuno': [
        {'nombre': 'Avena', 'gramos': '40', 'unidad': 'g'},
        {'nombre': 'Leche entera', 'gramos': '200', 'unidad': 'ml'},
        {'nombre': 'Fruta de mano (entera)', 'gramos': '1', 'unidad': 'und'},
      ],
      'Almuerzo': [
        {'nombre': 'Arroz cocido', 'gramos': '170', 'unidad': 'g'},
        {'nombre': 'Fríjoles / Lentejas cocidos', 'gramos': '60', 'unidad': 'g'},
        {'nombre': 'Queso', 'gramos': '35', 'unidad': 'g'},
        {'nombre': 'Ensalada mixta', 'gramos': '100', 'unidad': 'g'},
        {'nombre': 'Agua', 'gramos': '250', 'unidad': 'ml'},
      ],
      'Cena': [
        {'nombre': 'Arroz cocido', 'gramos': '170', 'unidad': 'g'},
        {'nombre': 'Huevo', 'gramos': '1', 'unidad': 'und'},
        {'nombre': 'Verduras al vapor', 'gramos': '100', 'unidad': 'g'},
        {'nombre': 'Agua', 'gramos': '250', 'unidad': 'ml'},
      ],
      'Refrigerio': [
        {'nombre': 'Yogur', 'gramos': '100', 'unidad': 'g'},
        {'nombre': 'Fruta de mano (entera)', 'gramos': '1', 'unidad': 'und'},
      ],
    },
  },
  // ── 20. Gestantes y Lactantes ─────────────────────────────────────────────
  {
    'nombre': 'Gestantes y Lactantes',
    'descripcion': 'Gestación y lactancia. Incremento de proteínas, calcio, hierro y ácido fólico.',
    'tiempos': {
      'Desayuno': [
        {'nombre': 'Avena', 'gramos': '40', 'unidad': 'g'},
        {'nombre': 'Leche entera', 'gramos': '200', 'unidad': 'ml'},
        {'nombre': 'Huevo', 'gramos': '1', 'unidad': 'und'},
        {'nombre': 'Fruta de mano (entera)', 'gramos': '1', 'unidad': 'und'},
      ],
      'Almuerzo': [
        {'nombre': 'Arroz cocido', 'gramos': '170', 'unidad': 'g'},
        {'nombre': 'Carne de res cocida', 'gramos': '78', 'unidad': 'g'},
        {'nombre': 'Fríjoles / Lentejas cocidos', 'gramos': '60', 'unidad': 'g'},
        {'nombre': 'Ensalada mixta', 'gramos': '100', 'unidad': 'g'},
        {'nombre': 'Naranja', 'gramos': '1', 'unidad': 'und'},
        {'nombre': 'Agua', 'gramos': '250', 'unidad': 'ml'},
      ],
      'Cena': [
        {'nombre': 'Arroz cocido', 'gramos': '170', 'unidad': 'g'},
        {'nombre': 'Pescado', 'gramos': '1', 'unidad': 'und'},
        {'nombre': 'Tubérculo (papa/yuca/plátano)', 'gramos': '80', 'unidad': 'g'},
        {'nombre': 'Verduras al vapor', 'gramos': '100', 'unidad': 'g'},
        {'nombre': 'Agua', 'gramos': '250', 'unidad': 'ml'},
      ],
      'Refrigerio': [
        {'nombre': 'Leche entera', 'gramos': '200', 'unidad': 'ml'},
        {'nombre': 'Fruta de mano (entera)', 'gramos': '1', 'unidad': 'und'},
      ],
    },
  },
];

// ---------------------------------------------------------------------------
// Main screen
// ---------------------------------------------------------------------------

class NutricionMenusScreen extends StatefulWidget {
  final String userId;
  final String empresaId;
  final String establecimiento;
  final DateTime semana;
  final bool showAppBar;
  final String appBarTitle;

  const NutricionMenusScreen({
    super.key,
    required this.userId,
    required this.empresaId,
    required this.establecimiento,
    required this.semana,
    this.showAppBar = true,
    this.appBarTitle = 'Plan alimentario',
  });

  @override
  State<NutricionMenusScreen> createState() => _NutricionMenusScreenState();
}

class _NutricionMenusScreenState extends State<NutricionMenusScreen> {
  final NutricionService _svc = NutricionService();
  late Stream<List<Map<String, dynamic>>> _menus$;

  // Static: seed solo una vez por sesión (no en cada rebuild del widget)
  static bool _plantillasSeeded = false;

  @override
  void initState() {
    super.initState();
    _rebuildStream();
    _seedPlantillas();
  }

  void _rebuildStream() {
    _menus$ = _svc.streamMenus(
      empresaId: widget.empresaId,
      establecimiento: widget.establecimiento,
      semana: widget.semana,
    );
  }

  /// Siembra/actualiza todas las plantillas base usando set(merge:true).
  /// Solo corre una vez por sesión de app (static guard).
  Future<void> _seedPlantillas() async {
    if (_plantillasSeeded) return;
    _plantillasSeeded = true;
    try {
      for (final d in kDietasDefault) {
        final nombre = d['nombre'] as String;
        final plantillaKey = nombre
            .toLowerCase()
            .replaceAll(' ', '_')
            .replaceAll('/', '_');
        final tiempos =
            (d['tiempos'] as Map<String, dynamic>).cast<String, dynamic>();
        final grupos = <String, List<Map<String, dynamic>>>{};
        for (final t in kTiemposComida) {
          final items = tiempos[t] as List<dynamic>? ?? [];
          grupos[t] = items
              .map((i) => {
                    'nombre': (i as Map)['nombre']?.toString() ?? '',
                    'gramos': i['gramos']?.toString() ?? '',
                    'unidad': i['unidad']?.toString() ?? 'g',
                  })
              .toList();
        }
        await _svc.guardarPlantillaMenu(
          empresaId: widget.empresaId,
          establecimiento: widget.establecimiento,
          plantillaKey: plantillaKey,
          titulo: nombre,
          descripcion: d['descripcion'] as String,
          grupos: grupos,
          userId: widget.userId,
        );
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Nutricion] seed plantillas: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isWide = MediaQuery.of(context).size.width >= 900;

    final body = StreamBuilder<List<Map<String, dynamic>>>(
      stream: _menus$,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
                  const SizedBox(height: 16),
                  const Text('No se pudieron cargar los menús.',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: NutritionPalette.textMain)),
                  const SizedBox(height: 8),
                  const Text('Verifica la conexión o vuelve a intentarlo.',
                      style: TextStyle(color: NutritionPalette.textMuted),
                      textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: () => setState(() => _rebuildStream()),
                    icon: const Icon(Icons.refresh),
                    label: const Text('REINTENTAR'),
                  ),
                ],
              ),
            ),
          );
        }
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final menus = snap.data!;
        if (menus.isEmpty) return _buildEmpty();

        return ListView.separated(
          padding:
              EdgeInsets.fromLTRB(isWide ? 32 : 16, 16, isWide ? 32 : 16, 100),
          itemCount: menus.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (_, i) => _DietaCard(
            menu: menus[i],
            onEdit: () => _abrirEditorDieta(menus[i]),
            onDelete: () => _eliminarMenu(menus[i]),
          ),
        );
      },
    );

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!widget.showAppBar) _buildWebContext(),
        Expanded(child: body),
      ],
    );

    if (!widget.showAppBar) {
      return Scaffold(
        backgroundColor: NutritionPalette.background,
        body: content,
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _abrirCrearDieta,
          icon: const Icon(Icons.add),
          label: const Text('NUEVA DIETA',
              style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.5)),
          backgroundColor: NutritionPalette.accent,
          foregroundColor: Colors.white,
        ),
      );
    }

    return Scaffold(
      backgroundColor: NutritionPalette.background,
      appBar: AppBar(
        title: Text(widget.appBarTitle,
            style: const TextStyle(fontFamily: kArial, fontWeight: FontWeight.bold)),
        backgroundColor: NutritionPalette.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _abrirCrearDieta,
            tooltip: 'Nueva Dieta',
          ),
        ],
      ),
      body: content,
    );
  }

  Widget _buildWebContext() {
    return const Padding(
      padding: EdgeInsets.fromLTRB(32, 24, 32, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('PLANIFICACIÓN',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  color: NutritionPalette.accent,
                  fontFamily: kArial)),
          SizedBox(height: 8),
          Text('Gestión de Planes Alimentarios',
              style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: NutritionPalette.textMain,
                  fontFamily: kArial)),
          SizedBox(height: 8),
          Text('Configura las minutas diarias y semanales por paciente o establecimiento.',
              style: TextStyle(
                  fontSize: 14, color: NutritionPalette.textMuted, fontFamily: kArial)),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.restaurant_menu_outlined,
              size: 64, color: NutritionPalette.textMuted),
          const SizedBox(height: 16),
          const Text('Sin planes alimentarios',
              style: TextStyle(
                  fontWeight: FontWeight.bold, color: NutritionPalette.textMain)),
          const SizedBox(height: 8),
          const Text('Crea un plan nuevo o parte de una plantilla institucional.',
              textAlign: TextAlign.center,
              style: TextStyle(color: NutritionPalette.textMuted)),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _abrirCrearDieta,
            icon: const Icon(Icons.add),
            label: const Text('CREAR PLAN'),
            style: FilledButton.styleFrom(backgroundColor: NutritionPalette.accent),
          ),
        ],
      ),
    );
  }

  // ── Crear dieta/plan ──────────────────────────────────────────────────────
  Future<void> _abrirCrearDieta() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CrearDietaDialog(
        svc: _svc,
        empresaId: widget.empresaId,
        establecimiento: widget.establecimiento,
        userId: widget.userId,
        semana: widget.semana,
      ),
    );
  }

  // ── Editar dieta/plan ─────────────────────────────────────────────────────
  Future<void> _abrirEditorDieta(Map<String, dynamic> menu) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _EditorDietaDialog(
        menu: menu,
        svc: _svc,
        userId: widget.userId,
        empresaId: widget.empresaId,
      ),
    );
  }

  // ── Eliminar dieta/plan ───────────────────────────────────────────────────
  Future<void> _eliminarMenu(Map<String, dynamic> menu) async {
    final nombre = menu['nombre']?.toString() ?? 'este plan';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Eliminar Plan',
            style: TextStyle(fontWeight: FontWeight.bold, fontFamily: kArial)),
        content: Text(
            '¿Deseas eliminar el plan "$nombre"?\n\nEsta acción no se puede deshacer.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('CANCELAR')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red[800]),
            child: const Text('ELIMINAR'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final menuId = menu['id']?.toString() ?? menu['menuId']?.toString() ?? '';
    if (menuId.isEmpty) return;
    try {
      await _svc.eliminarMenu(menuId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Plan "$nombre" eliminado'),
            backgroundColor: Colors.green[800],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al eliminar: $e'),
            backgroundColor: Colors.red[800],
          ),
        );
      }
    }
  }
}

// ---------------------------------------------------------------------------
// _DietaCard — tarjeta de menú con botones editar y eliminar
// ---------------------------------------------------------------------------

class _DietaCard extends StatelessWidget {
  final Map<String, dynamic> menu;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _DietaCard(
      {required this.menu, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final nombre = menu['nombre']?.toString() ?? 'Sin nombre';
    final raw =
        menu['itemsDetalladosPorTiempoComida'] ?? menu['itemsPorTiempoComida'];
    final detalles = _extractDetallePorTiempo(raw);
    int total = 0;
    for (final items in detalles.values) {
      total += items.length;
    }

    return NutritionCard(
      title: nombre.toUpperCase(),
      subtitle: '$total alimentos distribuidos en el plan diario',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(Icons.delete_outline, color: Colors.red[400], size: 22),
            onPressed: onDelete,
            tooltip: 'Eliminar Plan',
          ),
          IconButton(
            icon: const Icon(Icons.edit_note,
                color: NutritionPalette.accent, size: 28),
            onPressed: onEdit,
            tooltip: 'Editar Plan Alimentario',
          ),
        ],
      ),
      padding: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: kTiemposComida.map((t) {
            final color = kColorTiempo[t] ?? Colors.grey;
            final items = detalles[t] ?? const <Map<String, String>>[];
            return Container(
              width: 280,
              decoration: BoxDecoration(
                color: NutritionPalette.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: NutritionPalette.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    color: color.withOpacity(0.08),
                    child: Row(
                      children: [
                        Icon(kIconosTiempo[t], size: 16, color: color),
                        const SizedBox(width: 8),
                        Text(t.toUpperCase(),
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                color: color,
                                letterSpacing: 0.5)),
                        const Spacer(),
                        Text('${items.length} items',
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: color.withOpacity(0.8))),
                      ],
                    ),
                  ),
                  if (items.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('Sin alimentos configurados',
                          style: TextStyle(
                              fontSize: 11,
                              color: NutritionPalette.textMuted,
                              fontStyle: FontStyle.italic)),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final item in items.take(4))
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Row(
                                children: [
                                  const Icon(Icons.circle,
                                      size: 4, color: NutritionPalette.textMuted),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _formatDetalle(item),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontSize: 12,
                                          color: NutritionPalette.textMain,
                                          fontWeight: FontWeight.w500),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (items.length > 4)
                            Padding(
                              padding: const EdgeInsets.only(top: 4, left: 12),
                              child: Text(
                                '+ ${items.length - 4} alimentos adicionales',
                                style: const TextStyle(
                                    fontSize: 10,
                                    color: NutritionPalette.accent,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Map<String, List<Map<String, String>>> _extractDetallePorTiempo(Object? raw) {
    final result = <String, List<Map<String, String>>>{};
    if (raw is! Map) return result;
    for (final entry in raw.entries) {
      final tiempo = entry.key.toString();
      final values = entry.value is List ? entry.value as List : const [];
      result[tiempo] = values
          .map((item) {
            if (item is Map) {
              return {
                'nombre': item['nombre']?.toString() ?? '',
                'gramos': item['gramos']?.toString() ?? '',
                'unidad': item['unidad']?.toString() ?? '',
              };
            }
            return {'nombre': item.toString(), 'gramos': '', 'unidad': ''};
          })
          .where((item) => (item['nombre'] ?? '').isNotEmpty)
          .toList();
    }
    return result;
  }

  String _formatDetalle(Map<String, String> item) {
    final nombre = item['nombre'] ?? '';
    final gramos = (item['gramos'] ?? '').trim();
    final unidad = (item['unidad'] ?? '').trim();
    if (gramos.isEmpty && unidad.isEmpty) return nombre;
    if (unidad.isEmpty) return '$nombre · $gramos';
    return '$nombre · $gramos $unidad';
  }
}

// ---------------------------------------------------------------------------
// _ItemEntry — modelo mutable de ingrediente para los editores
// ---------------------------------------------------------------------------

class _ItemEntry {
  final String nombre;
  final String unidad;
  final String? ingredienteId;
  final TextEditingController gramosCtrl;

  _ItemEntry({
    required this.nombre,
    required this.unidad,
    required String gramos,
    this.ingredienteId,
  }) : gramosCtrl = TextEditingController(text: gramos);

  Map<String, dynamic> toMap() => {
        'nombre': nombre,
        'gramos': gramosCtrl.text.trim(),
        'unidad': unidad,
        if (ingredienteId != null && ingredienteId!.isNotEmpty)
          'ingredienteId': ingredienteId,
      };

  void dispose() => gramosCtrl.dispose();
}

// ---------------------------------------------------------------------------
// _CrearDietaDialog — wizard completo: nombre → template opcional → ingredientes
// ---------------------------------------------------------------------------

class _CrearDietaDialog extends StatefulWidget {
  final NutricionService svc;
  final String empresaId;
  final String establecimiento;
  final String userId;
  final DateTime semana;

  const _CrearDietaDialog({
    required this.svc,
    required this.empresaId,
    required this.establecimiento,
    required this.userId,
    required this.semana,
  });

  @override
  State<_CrearDietaDialog> createState() => _CrearDietaDialogState();
}

class _CrearDietaDialogState extends State<_CrearDietaDialog>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  late final Map<String, List<_ItemEntry>> _items;
  final _nombreCtrl = TextEditingController();
  Map<String, dynamic>? _templateSel;
  bool _saving = false;
  bool _nombreVacio = false;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: kTiemposComida.length, vsync: this);
    _items = {for (final t in kTiemposComida) t: <_ItemEntry>[]};
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _nombreCtrl.dispose();
    for (final entries in _items.values) {
      for (final e in entries) e.dispose();
    }
    super.dispose();
  }

  void _aplicarTemplate(Map<String, dynamic>? template) {
    if (template == null) return;
    // Dispose existing
    for (final entries in _items.values) {
      for (final e in entries) e.dispose();
    }
    for (final t in kTiemposComida) {
      _items[t] = [];
    }
    final tiempos =
        (template['tiempos'] as Map<String, dynamic>?)?.cast<String, dynamic>() ?? {};
    for (final t in kTiemposComida) {
      final list = tiempos[t] as List<dynamic>? ?? [];
      _items[t] = list
          .map((i) {
            if (i is Map) {
              return _ItemEntry(
                nombre: i['nombre']?.toString() ?? '',
                unidad: i['unidad']?.toString() ?? 'g',
                gramos: i['gramos']?.toString() ?? '',
              );
            }
            return _ItemEntry(nombre: i.toString(), unidad: 'g', gramos: '');
          })
          .where((e) => e.nombre.isNotEmpty)
          .toList();
    }
    setState(() {
      _templateSel = template;
      if (_nombreCtrl.text.trim().isEmpty) {
        _nombreCtrl.text = template['nombre']?.toString() ?? '';
        _nombreVacio = false;
      }
    });
  }

  Future<void> _agregarIngrediente(String tiempo) async {
    final resultado = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _PickIngredienteDialog(
        svc: widget.svc,
        empresaId: widget.empresaId,
        userId: widget.userId,
      ),
    );
    if (resultado == null || !mounted) return;
    setState(() {
      _items[tiempo]!.add(_ItemEntry(
        nombre: resultado['nombre']?.toString() ?? '',
        unidad: resultado['unidad']?.toString() ?? 'g',
        gramos: resultado['gramos']?.toString() ?? '',
        ingredienteId: resultado['id']?.toString(),
      ));
    });
  }

  void _removerItem(String tiempo, int index) {
    setState(() {
      final e = _items[tiempo]!.removeAt(index);
      e.dispose();
    });
  }

  Future<void> _crear() async {
    final nombre = _nombreCtrl.text.trim();
    if (nombre.isEmpty) {
      setState(() => _nombreVacio = true);
      return;
    }
    setState(() => _saving = true);
    try {
      final itemsDet = <String, List<Map<String, dynamic>>>{};
      final itemsSimple = <String, List<String>>{};
      for (final t in kTiemposComida) {
        final entries = _items[t] ?? [];
        itemsDet[t] = entries.map((e) => e.toMap()).toList();
        itemsSimple[t] = entries.map((e) => e.nombre).toList();
      }
      await widget.svc.crearMenu(
        empresaId: widget.empresaId,
        userId: widget.userId,
        nombre: nombre,
        periodo: 'Semanal',
        establecimiento: widget.establecimiento,
        semana: widget.semana,
        itemsPorTiempoComida: itemsSimple,
        itemsDetalladosPorTiempoComida: itemsDet,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red[800]));
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 700;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      insetPadding:
          EdgeInsets.symmetric(horizontal: isWide ? 60 : 12, vertical: 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Header ──────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
            child: Row(
              children: [
                const Icon(Icons.restaurant_menu, color: NutritionPalette.accent),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Nueva Dieta / Plan',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontFamily: kArial,
                          fontSize: 16,
                          color: NutritionPalette.textMain)),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: _saving ? null : () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // ── Paso 1: Nombre ───────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: TextField(
              controller: _nombreCtrl,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Nombre del plan *',
                hintText: 'Ej: Dieta Hipocalórica Pabellón 3',
                border: const OutlineInputBorder(),
                errorText: _nombreVacio ? 'El nombre es obligatorio' : null,
                prefixIcon: const Icon(Icons.drive_file_rename_outline),
              ),
              onChanged: (_) {
                if (_nombreVacio) setState(() => _nombreVacio = false);
              },
            ),
          ),
          // ── Paso 2: Plantilla base (opcional) ────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: DropdownButtonFormField<Map<String, dynamic>>(
              value: _templateSel,
              decoration: const InputDecoration(
                labelText: 'Basarse en plantilla (opcional)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.library_books_outlined),
              ),
              isExpanded: true,
              hint: const Text('Ninguna — comenzar en blanco'),
              items: [
                const DropdownMenuItem<Map<String, dynamic>>(
                  value: null,
                  child: Text('— Comenzar en blanco —',
                      style: TextStyle(fontStyle: FontStyle.italic)),
                ),
                ...kDietasDefault.map((d) => DropdownMenuItem<Map<String, dynamic>>(
                      value: d,
                      child: Text(d['nombre'] as String),
                    )),
              ],
              onChanged: _saving ? null : _aplicarTemplate,
            ),
          ),
          // ── Paso 3: Ingredientes por tiempo de comida ─────────────────────
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                Icon(Icons.restaurant, size: 14, color: NutritionPalette.textMuted),
                SizedBox(width: 6),
                Text('Ingredientes por tiempo de comida',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: NutritionPalette.textMuted)),
              ],
            ),
          ),
          TabBar(
            controller: _tabCtrl,
            isScrollable: true,
            labelColor: NutritionPalette.accent,
            unselectedLabelColor: NutritionPalette.textMuted,
            indicatorColor: NutritionPalette.accent,
            tabs: kTiemposComida
                .map((t) => Tab(icon: Icon(kIconosTiempo[t], size: 16), text: t))
                .toList(),
          ),
          SizedBox(
            height: 300,
            child: TabBarView(
              controller: _tabCtrl,
              children: kTiemposComida
                  .map((t) => _buildTiempoTab(t))
                  .toList(),
            ),
          ),
          const Divider(height: 1),
          // ── Footer ──────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _saving ? null : () => Navigator.pop(context),
                  child: const Text('CANCELAR'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _saving ? null : _crear,
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.add, size: 18),
                  label: const Text('CREAR PLAN'),
                  style:
                      FilledButton.styleFrom(backgroundColor: NutritionPalette.accent),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTiempoTab(String tiempo) {
    final items = _items[tiempo] ?? [];
    final color = kColorTiempo[tiempo] ?? NutritionPalette.accent;
    return Column(
      children: [
        Expanded(
          child: items.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(kIconosTiempo[tiempo],
                          size: 32, color: NutritionPalette.textMuted),
                      const SizedBox(height: 8),
                      Text('Sin ingredientes en $tiempo',
                          style: const TextStyle(color: NutritionPalette.textMuted)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  itemCount: items.length,
                  itemBuilder: (_, i) => _buildItemRow(tiempo, i, items[i], color),
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: OutlinedButton.icon(
            onPressed: () => _agregarIngrediente(tiempo),
            icon: Icon(Icons.add, color: color, size: 16),
            label: Text('Agregar ingrediente a $tiempo',
                style: TextStyle(
                    color: color, fontSize: 12, fontWeight: FontWeight.w700)),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: color.withOpacity(0.5)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildItemRow(String tiempo, int index, _ItemEntry entry, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: NutritionPalette.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: NutritionPalette.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.drag_handle, size: 16, color: NutritionPalette.textMuted),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: Text(entry.nombre,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: NutritionPalette.textMain),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 60,
            height: 34,
            child: TextField(
              controller: entry.gramosCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(color: color),
                ),
                hintText: '—',
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 30,
            child: Text(entry.unidad,
                style: const TextStyle(
                    fontSize: 10, color: NutritionPalette.textMuted),
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis),
          ),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline,
                size: 18, color: Colors.redAccent),
            onPressed: () => _removerItem(tiempo, index),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            tooltip: 'Eliminar',
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _EditorDietaDialog — editor real con tabs (edición de menú existente)
// ---------------------------------------------------------------------------

class _EditorDietaDialog extends StatefulWidget {
  final Map<String, dynamic> menu;
  final NutricionService svc;
  final String userId;
  final String empresaId;

  const _EditorDietaDialog({
    required this.menu,
    required this.svc,
    required this.userId,
    required this.empresaId,
  });

  @override
  State<_EditorDietaDialog> createState() => _EditorDietaDialogState();
}

class _EditorDietaDialogState extends State<_EditorDietaDialog>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  late final Map<String, List<_ItemEntry>> _items;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: kTiemposComida.length, vsync: this);
    _items = {};
    final raw = widget.menu['itemsDetalladosPorTiempoComida'] ??
        widget.menu['itemsPorTiempoComida'];
    for (final t in kTiemposComida) {
      _items[t] = [];
      if (raw is Map) {
        final list = raw[t];
        if (list is List) {
          for (final item in list) {
            if (item is Map) {
              final nombre = item['nombre']?.toString() ?? '';
              if (nombre.isEmpty) continue;
              _items[t]!.add(_ItemEntry(
                nombre: nombre,
                unidad: item['unidad']?.toString() ?? 'g',
                gramos: item['gramos']?.toString() ?? '',
                ingredienteId: item['ingredienteId']?.toString(),
              ));
            } else if (item is String && item.isNotEmpty) {
              _items[t]!.add(_ItemEntry(nombre: item, unidad: 'g', gramos: ''));
            }
          }
        }
      }
    }
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    for (final entries in _items.values) {
      for (final e in entries) e.dispose();
    }
    super.dispose();
  }

  Future<void> _agregarIngrediente(String tiempo) async {
    final resultado = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _PickIngredienteDialog(
        svc: widget.svc,
        empresaId: widget.empresaId,
        userId: widget.userId,
      ),
    );
    if (resultado == null || !mounted) return;
    setState(() {
      _items[tiempo]!.add(_ItemEntry(
        nombre: resultado['nombre']?.toString() ?? '',
        unidad: resultado['unidad']?.toString() ?? 'g',
        gramos: resultado['gramos']?.toString() ?? '',
        ingredienteId: resultado['id']?.toString(),
      ));
    });
  }

  void _removerItem(String tiempo, int index) {
    setState(() {
      final e = _items[tiempo]!.removeAt(index);
      e.dispose();
    });
  }

  Future<void> _guardar() async {
    setState(() => _saving = true);
    try {
      final itemsDet = <String, List<Map<String, dynamic>>>{};
      final itemsSimple = <String, List<String>>{};
      for (final t in kTiemposComida) {
        final entries = _items[t] ?? [];
        itemsDet[t] = entries.map((e) => e.toMap()).toList();
        itemsSimple[t] = entries.map((e) => e.nombre).toList();
      }
      final menuId = widget.menu['id']?.toString() ??
          widget.menu['menuId']?.toString() ??
          '';
      if (menuId.isEmpty) throw Exception('ID de menú no encontrado');
      await widget.svc.actualizarMenu(
        menuId: menuId,
        userId: widget.userId,
        nombre: widget.menu['nombre']?.toString() ?? '',
        periodo: widget.menu['periodo']?.toString() ?? 'Semanal',
        itemsPorTiempoComida: itemsSimple,
        itemsDetalladosPorTiempoComida: itemsDet,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Error al guardar: $e'),
            backgroundColor: Colors.red[800]));
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 700;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      insetPadding:
          EdgeInsets.symmetric(horizontal: isWide ? 60 : 12, vertical: 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
            child: Row(
              children: [
                const Icon(Icons.edit_note, color: NutritionPalette.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Editar: ${widget.menu['nombre'] ?? ''}',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontFamily: kArial,
                          fontSize: 16,
                          color: NutritionPalette.textMain)),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: _saving ? null : () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          TabBar(
            controller: _tabCtrl,
            isScrollable: true,
            labelColor: NutritionPalette.accent,
            unselectedLabelColor: NutritionPalette.textMuted,
            indicatorColor: NutritionPalette.accent,
            tabs: kTiemposComida
                .map((t) => Tab(icon: Icon(kIconosTiempo[t], size: 16), text: t))
                .toList(),
          ),
          SizedBox(
            height: 380,
            child: TabBarView(
              controller: _tabCtrl,
              children: kTiemposComida.map((t) => _buildTiempoTab(t)).toList(),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _saving ? null : () => Navigator.pop(context),
                  child: const Text('CANCELAR'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _saving ? null : _guardar,
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.save, size: 18),
                  label: const Text('GUARDAR CAMBIOS'),
                  style:
                      FilledButton.styleFrom(backgroundColor: NutritionPalette.accent),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTiempoTab(String tiempo) {
    final items = _items[tiempo] ?? [];
    final color = kColorTiempo[tiempo] ?? NutritionPalette.accent;
    return Column(
      children: [
        Expanded(
          child: items.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(kIconosTiempo[tiempo],
                          size: 36, color: NutritionPalette.textMuted),
                      const SizedBox(height: 8),
                      Text('Sin ingredientes en $tiempo',
                          style: const TextStyle(color: NutritionPalette.textMuted)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  itemCount: items.length,
                  itemBuilder: (_, i) => _buildItemRow(tiempo, i, items[i], color),
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
          child: OutlinedButton.icon(
            onPressed: () => _agregarIngrediente(tiempo),
            icon: Icon(Icons.add, color: color, size: 16),
            label: Text('Agregar ingrediente',
                style: TextStyle(
                    color: color, fontSize: 12, fontWeight: FontWeight.w700)),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: color.withOpacity(0.5)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildItemRow(String tiempo, int index, _ItemEntry entry, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: NutritionPalette.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: NutritionPalette.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.drag_handle, size: 16, color: NutritionPalette.textMuted),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: Text(entry.nombre,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: NutritionPalette.textMain),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 60,
            height: 34,
            child: TextField(
              controller: entry.gramosCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(color: color),
                ),
                hintText: '—',
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 30,
            child: Text(entry.unidad,
                style: const TextStyle(
                    fontSize: 10, color: NutritionPalette.textMuted),
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis),
          ),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline,
                size: 18, color: Colors.redAccent),
            onPressed: () => _removerItem(tiempo, index),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            tooltip: 'Eliminar',
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _PickIngredienteDialog — busca y selecciona desde TBL_INGREDIENTES
// ---------------------------------------------------------------------------

class _PickIngredienteDialog extends StatefulWidget {
  final NutricionService svc;
  final String empresaId;
  final String userId;

  const _PickIngredienteDialog({
    required this.svc,
    required this.empresaId,
    required this.userId,
  });

  @override
  State<_PickIngredienteDialog> createState() => _PickIngredienteDialogState();
}

class _PickIngredienteDialogState extends State<_PickIngredienteDialog> {
  final _searchCtrl = TextEditingController();
  final _gramosCtrl = TextEditingController();
  String _busqueda = '';
  String _categoria = 'Todos';
  Map<String, dynamic>? _seleccionado;

  @override
  void dispose() {
    _searchCtrl.dispose();
    _gramosCtrl.dispose();
    super.dispose();
  }

  Future<void> _crearNuevo() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _NuevoIngredienteQuickDialog(
        svc: widget.svc,
        empresaId: widget.empresaId,
        userId: widget.userId,
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _seleccionado = result;
        _gramosCtrl.text = result['gramosStd']?.toString() ?? '';
      });
    }
  }

  void _confirmar() {
    if (_seleccionado == null) return;
    final gramos = _gramosCtrl.text.trim().isNotEmpty
        ? _gramosCtrl.text.trim()
        : (_seleccionado!['gramosStd']?.toString() ?? '');
    Navigator.pop(context, {..._seleccionado!, 'gramos': gramos});
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 700;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      insetPadding:
          EdgeInsets.symmetric(horizontal: isWide ? 100 : 16, vertical: 40),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
            child: Row(
              children: [
                const Icon(Icons.search, color: NutritionPalette.accent),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Seleccionar Ingrediente',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontFamily: kArial,
                          fontSize: 16)),
                ),
                IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context)),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Buscar por nombre del alimento…',
                prefixIcon: const Icon(Icons.search, size: 18),
                filled: true,
                fillColor: NutritionPalette.surface,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: NutritionPalette.accent),
                ),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _busqueda = v.toLowerCase().trim()),
            ),
          ),
          SizedBox(
            height: 38,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
              scrollDirection: Axis.horizontal,
              itemCount: kCategorias.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (_, i) {
                final cat = kCategorias[i];
                final active = _categoria == cat;
                final color = cat == 'Todos'
                    ? NutritionPalette.accent
                    : (kColorCategoria[cat] ?? Colors.grey);
                return FilterChip(
                  selected: active,
                  label: Text(cat,
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: active ? Colors.white : color)),
                  selectedColor: color,
                  backgroundColor: NutritionPalette.surface,
                  side: BorderSide(
                      color: active ? color : NutritionPalette.border),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4)),
                  onSelected: (_) => setState(() {
                    _categoria = cat;
                    _seleccionado = null;
                  }),
                );
              },
            ),
          ),
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: widget.svc.streamIngredientes(
                empresaId: widget.empresaId,
                categoria: _categoria == 'Todos' ? null : _categoria,
              ),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                var items = snap.data ?? [];
                if (_busqueda.isNotEmpty) {
                  items = items
                      .where((i) =>
                          (i['nombre']?.toString().toLowerCase() ?? '')
                              .contains(_busqueda))
                      .toList();
                }
                if (items.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.search_off,
                            size: 40, color: NutritionPalette.textMuted),
                        const SizedBox(height: 8),
                        const Text('Sin resultados',
                            style: TextStyle(color: NutritionPalette.textMuted)),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _crearNuevo,
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('Crear nuevo ingrediente'),
                        ),
                      ],
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  itemCount: items.length,
                  itemBuilder: (_, i) {
                    final ing = items[i];
                    final sel = _seleccionado?['id'] == ing['id'];
                    final cat = ing['categoria']?.toString() ?? 'Otro';
                    final color = kColorCategoria[cat] ?? Colors.grey;
                    return InkWell(
                      onTap: () => setState(() {
                        _seleccionado = ing;
                        _gramosCtrl.text = ing['gramosStd']?.toString() ?? '';
                      }),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: sel
                              ? NutritionPalette.accent.withOpacity(0.08)
                              : NutritionPalette.surface,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                              color: sel
                                  ? NutritionPalette.accent
                                  : NutritionPalette.border),
                        ),
                        child: Row(
                          children: [
                            sel
                                ? const Icon(Icons.check_circle,
                                    size: 16, color: NutritionPalette.accent)
                                : Icon(
                                    kIconoCategoria[cat] ??
                                        Icons.category_outlined,
                                    size: 16,
                                    color: color),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(ing['nombre']?.toString() ?? '',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13)),
                                  Text(cat.toUpperCase(),
                                      style: TextStyle(
                                          fontSize: 9,
                                          color: color,
                                          fontWeight: FontWeight.w800)),
                                ],
                              ),
                            ),
                            Text(
                              '${ing['gramosStd'] ?? ''} ${ing['unidad'] ?? 'g'}',
                              style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: NutritionPalette.accent),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          if (_seleccionado != null)
            Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
              decoration: const BoxDecoration(
                color: Color(0xFFF0FDF4),
                border: Border(top: BorderSide(color: NutritionPalette.border)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_outline,
                      size: 16, color: NutritionPalette.accent),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(_seleccionado!['nombre']?.toString() ?? '',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: NutritionPalette.textMain),
                        overflow: TextOverflow.ellipsis),
                  ),
                  const SizedBox(width: 8),
                  const Text('Cant:',
                      style: TextStyle(
                          fontSize: 11, color: NutritionPalette.textMuted)),
                  const SizedBox(width: 4),
                  SizedBox(
                    width: 65,
                    height: 34,
                    child: TextField(
                      controller: _gramosCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.bold),
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4)),
                        isDense: true,
                        hintText: _seleccionado!['gramosStd']?.toString() ?? '',
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(_seleccionado!['unidad']?.toString() ?? 'g',
                      style: const TextStyle(
                          fontSize: 11, color: NutritionPalette.textMuted)),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
            child: Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _crearNuevo,
                  icon: const Icon(Icons.add, size: 14),
                  label: const Text('CREAR NUEVO',
                      style: TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w700)),
                ),
                const Spacer(),
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('CANCELAR')),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _seleccionado == null ? null : _confirmar,
                  style: FilledButton.styleFrom(
                      backgroundColor: NutritionPalette.accent),
                  child: const Text('AGREGAR'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _NuevoIngredienteQuickDialog — crear ingrediente nuevo desde el picker
// ---------------------------------------------------------------------------

class _NuevoIngredienteQuickDialog extends StatefulWidget {
  final NutricionService svc;
  final String empresaId;
  final String userId;

  const _NuevoIngredienteQuickDialog({
    required this.svc,
    required this.empresaId,
    required this.userId,
  });

  @override
  State<_NuevoIngredienteQuickDialog> createState() =>
      _NuevoIngredienteQuickDialogState();
}

class _NuevoIngredienteQuickDialogState
    extends State<_NuevoIngredienteQuickDialog> {
  late final TextEditingController _n, _g, _u;
  late String _c;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _n = TextEditingController();
    _g = TextEditingController();
    _u = TextEditingController(text: 'g');
    _c = 'Cereal';
  }

  @override
  void dispose() {
    _n.dispose();
    _g.dispose();
    _u.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_n.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      final docId = await widget.svc.guardarIngrediente(
        empresaId: widget.empresaId,
        userId: widget.userId,
        data: {
          'nombre': _n.text.trim(),
          'gramosStd': _g.text.trim(),
          'unidad': _u.text.trim(),
          'categoria': _c,
          'tiempos': <String>[],
        },
      );
      if (mounted) {
        Navigator.pop(context, {
          'id': docId,
          'nombre': _n.text.trim(),
          'gramosStd': _g.text.trim(),
          'unidad': _u.text.trim(),
          'categoria': _c,
        });
      }
    } catch (_) {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: const Text('Nuevo Ingrediente',
          style:
              TextStyle(fontWeight: FontWeight.bold, fontFamily: kArial)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _n,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Nombre *',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _c,
            items: kCategorias
                .where((x) => x != 'Todos')
                .map((x) => DropdownMenuItem(value: x, child: Text(x)))
                .toList(),
            onChanged: (v) => setState(() => _c = v!),
            decoration: const InputDecoration(
              labelText: 'Categoría',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _g,
                  decoration: const InputDecoration(
                    labelText: 'Cantidad estándar',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _u,
                  decoration: const InputDecoration(
                    labelText: 'Unidad',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCELAR')),
        FilledButton(
          onPressed: _saving ? null : _save,
          style: FilledButton.styleFrom(backgroundColor: NutritionPalette.accent),
          child: Text(_saving ? 'GUARDANDO…' : 'CREAR Y USAR'),
        ),
      ],
    );
  }
}

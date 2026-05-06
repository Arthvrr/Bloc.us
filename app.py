import streamlit as st
import json
import os
from datetime import datetime
import calendar
import pandas as pd
import plotly.express as px

st.set_page_config(page_title="Bloc.us", layout="wide")
st.title("📚 Bloc.us - Ton partenaire de blocus")

# -------------------------
# INIT & AUTO-SAVE
# -------------------------
DB_FILE = "blocus_data.json"

if "loaded" not in st.session_state:
    if os.path.exists(DB_FILE):
        with open(DB_FILE, "r", encoding="utf-8") as f:
            data = json.load(f)
            st.session_state.courses = data.get("courses", {})
            st.session_state.schedule = data.get("schedule", {})
            
            for c_name, c_data in st.session_state.courses.items():
                if "passing_grade" not in c_data: c_data["passing_grade"] = 10.0
                if "full_name" not in c_data: c_data["full_name"] = ""
                if "professor" not in c_data: c_data["professor"] = ""
                if "exam_location" not in c_data: c_data["exam_location"] = ""
                # Retro-compatibilité pour les heures d'examen
                if "exam_start_time" not in c_data: 
                    c_data["exam_start_time"] = c_data.pop("exam_time", "08:30")
                if "exam_end_time" not in c_data: 
                    c_data["exam_end_time"] = "10:30"
    else:
        st.session_state.courses = {}
        st.session_state.schedule = {}
    st.session_state.loaded = True

def auto_save():
    with open(DB_FILE, "w", encoding="utf-8") as f:
        json.dump({
            "courses": st.session_state.courses,
            "schedule": st.session_state.schedule
        }, f, indent=2)

# -------------------------
# UTILITAIRES
# -------------------------
def compute_progress(tasks):
    total_done = sum(t["done"] for t in tasks)
    total_possible = sum(t["total"] for t in tasks)
    return total_done / total_possible if total_possible else 0

def compute_exam_needed(grading, passing_grade=10.0):
    total_points = sum(g["total"] for g in grading)
    earned_points = sum(g["score"] for g in grading)
    exam_total = max(0, 20 - total_points)
    needed_exam = passing_grade - earned_points
    return round(exam_total, 2), round(max(0, needed_exam), 2)

# Barre de progression dynamique (is_main permet de la mettre en évidence)
def progress_bar(progress, color, is_main=False):
    height = "24px" if is_main else "14px"
    font_size = "16px" if is_main else "12px"
    font_weight = "bold" if is_main else "normal"
    margin_bottom = "15px" if is_main else "10px"
    
    st.markdown(f"""
    <div style="background:#eaeaea;border-radius:10px;height:{height};margin-bottom:5px;">
        <div style="
            background:{color};
            width:{progress*100}%;
            height:100%;
            border-radius:10px;
            transition:0.3s;
        "></div>
    </div>
    <div style="font-size:{font_size};font-weight:{font_weight};color:#555;margin-bottom:{margin_bottom};">
        {round(progress*100, 2)}% accompli
    </div>
    """, unsafe_allow_html=True)

# -------------------------
# SIDEBAR
# -------------------------
st.sidebar.header("⚙️ Gestion des cours")

new_course = st.sidebar.text_input("Acronyme du cours (ex: LINFO1234)")
color = st.sidebar.color_picker("Couleur", "#4CAF50")

if st.sidebar.button("Ajouter le cours"):
    if new_course and new_course not in st.session_state.courses:
        st.session_state.courses[new_course] = {
            "tasks": [],
            "color": color,
            "grading": [],
            "passing_grade": 10.0,
            "full_name": "",
            "professor": "",
            "exam_start_time": "08:30",
            "exam_end_time": "10:30",
            "exam_location": ""
        }
        auto_save()
        st.rerun()

if st.session_state.courses:
    c = st.sidebar.selectbox("Supprimer un cours", list(st.session_state.courses.keys()))
    if st.sidebar.button("❌ Supprimer"):
        del st.session_state.courses[c]
        auto_save()
        st.rerun()

# -------------------------
# CALCULS GLOBAUX
# -------------------------
courses = list(st.session_state.courses.keys())
today_str = datetime.today().strftime("%Y-%m-%d")

study_days_count = {c: {"total": 0, "remaining": 0} for c in courses}

for date_str, events in st.session_state.schedule.items():
    for e in events:
        if e["type"] == "Étude" and e["course"] in study_days_count:
            study_days_count[e["course"]]["total"] += 1
            if date_str >= today_str:
                study_days_count[e["course"]]["remaining"] += 1

# -------------------------
# TABS
# -------------------------
tabs = ["📊 Général", "📅 Planning"] + courses
tab_objs = st.tabs(tabs)

# -------------------------
# 1. GENERAL
# -------------------------
with tab_objs[0]:
    st.header("🎯 Focus du jour")
    
    todays_events = st.session_state.schedule.get(today_str, [])
    
    if todays_events:
        for ev in todays_events:
            c = ev["course"]
            if c not in st.session_state.courses: continue
            
            if ev["type"] == "Examen":
                ex_start = st.session_state.courses[c].get("exam_start_time", "08:30")
                ex_end = st.session_state.courses[c].get("exam_end_time", "10:30")
                ex_loc = st.session_state.courses[c].get("exam_location", "À définir")
                
                st.error(f"""
                ### 🚨 EXAMEN AUJOURD'HUI : {c}
                **🕒 Heure :** {ex_start} - {ex_end} &nbsp;&nbsp;|&nbsp;&nbsp; **📍 Lieu :** {ex_loc if ex_loc else 'Non défini'}
                
                Bon courage, donne tout !!
                """)
                if ev.get("description"):
                    st.write(f"📝 **Détails :** {ev['description']}")
            else:
                study_dates = [d for d, evs in st.session_state.schedule.items() for e in evs if e["course"] == c and e["type"] == "Étude"]
                study_dates.sort()
                
                try:
                    nth_day = study_dates.index(today_str) + 1
                except ValueError:
                    nth_day = 1
                    
                total_days = len(study_dates)
                prog = compute_progress(st.session_state.courses[c]["tasks"])
                col_color = st.session_state.courses[c]["color"]
                
                with st.container(border=True):
                    st.markdown(f"#### 📚 {c} — *Jour {nth_day} sur {total_days}*")
                    if ev.get("description"):
                        st.markdown(f"**🎯 Objectif :** {ev['description']}")
                    progress_bar(prog, col_color, is_main=True)
    else:
        st.success("🎉 Rien de prévu au calendrier aujourd'hui. Profite de ton temps libre pour te ressourcer !")

    st.divider()

    st.header("Vue d'ensemble de ton blocus")
    
    if courses:
        color_map = {c: st.session_state.courses[c]["color"] for c in courses}
        
        radar_data = [{"Cours": c, "Progression (%)": compute_progress(st.session_state.courses[c]["tasks"]) * 100} for c in courses]
        df_radar = pd.DataFrame(radar_data)
        
        pie_data = [{"Cours": c, "Jours alloués": study_days_count[c]["total"]} for c in courses if study_days_count[c]["total"] > 0]
        df_pie = pd.DataFrame(pie_data)
        
        bar_data = []
        for c in courses:
            data = st.session_state.courses[c]
            passing_target = data.get("passing_grade", 10.0)
            
            earned = sum(g["score"] for g in data["grading"])
            tot_graded = sum(g["total"] for g in data["grading"])
            exam_tot = max(0, 20 - tot_graded)
            
            needed = max(0, passing_target - earned)
            needed_from_exam = min(exam_tot, needed)
            bonus = max(0, exam_tot - needed_from_exam)
            
            bar_data.append({"Cours": c, "Type": "Acquis (déjà en poche)", "Points": earned})
            bar_data.append({"Cours": c, "Type": f"À réussir (Cible: {passing_target}/20)", "Points": needed_from_exam})
            bar_data.append({"Cours": c, "Type": "Bonus (au-dessus de la cible)", "Points": bonus})
            
        df_bar = pd.DataFrame(bar_data)

        col_chart1, col_chart2 = st.columns(2)
        
        with col_chart1:
            if len(courses) >= 3:
                fig_radar = px.line_polar(df_radar, r='Progression (%)', theta='Cours', line_close=True, title="Équilibre d'étude")
                fig_radar.update_traces(fill='toself', line_color="#4CAF50", fillcolor="rgba(76, 175, 80, 0.5)")
                fig_radar.update_layout(polar=dict(radialaxis=dict(range=[0, 100])))
                st.plotly_chart(fig_radar, use_container_width=True)
            else:
                fig_prog = px.bar(df_radar, x="Cours", y="Progression (%)", color="Cours", color_discrete_map=color_map, title="Équilibre d'étude")
                fig_prog.update_layout(yaxis=dict(range=[0, 100]))
                st.plotly_chart(fig_prog, use_container_width=True)
                
        with col_chart2:
            if not df_pie.empty:
                fig_pie = px.pie(df_pie, values='Jours alloués', names='Cours', title="Répartition du temps de blocus", color='Cours', color_discrete_map=color_map, hole=0.4)
                st.plotly_chart(fig_pie, use_container_width=True)
            else:
                st.info("Planifie des jours d'étude dans le calendrier pour voir la répartition de ton temps !")

        fig_bar_pts = px.bar(
            df_bar, x="Cours", y="Points", color="Type", 
            title="🎯 Stratégie des points (sur 20)",
            color_discrete_map={
                "Acquis (déjà en poche)": "#28a745", 
                "À réussir (Cible: {passing_target}/20)": "#ffc107",
                "Bonus (au-dessus de la cible)": "#e9ecef"
            }
        )
        fig_bar_pts.update_layout(barmode='stack', yaxis=dict(range=[0, 20]))
        st.plotly_chart(fig_bar_pts, use_container_width=True)

        st.divider()

        col1, col2 = st.columns(2)
        for i, c in enumerate(courses):
            target_col = col1 if i % 2 == 0 else col2
            data = st.session_state.courses[c]
            with target_col:
                st.subheader(c)
                st.write(f"⏱️ **Prévus :** {study_days_count[c]['total']} jour(s) | ⏳ **Restants :** {study_days_count[c]['remaining']} jour(s)")
                progress_bar(compute_progress(data["tasks"]), data["color"], is_main=True)
                st.markdown("<br>", unsafe_allow_html=True)
    else:
        st.info("Ajoute des cours dans le menu de gauche pour commencer sur Bloc.us !")

# -------------------------
# 2. PLANNING / CALENDRIER
# -------------------------
with tab_objs[1]:
    col_head1, col_head2 = st.columns([3, 1])
    with col_head1:
        st.header("Programme d'étude")
    with col_head2:
        st.write("") 
        if st.button("🗑️ Vider TOUT le calendrier", use_container_width=True):
            st.session_state.schedule = {}
            auto_save()
            st.rerun()
    
    with st.expander("➕ Planifier une session", expanded=True):
        col1, col2, col3 = st.columns([2, 2, 3])
        selected_date = col1.date_input("Date")
        event_type = col2.selectbox("Type", ["Étude", "Examen"])
        selected_course = col3.selectbox("Cours concerné", courses if courses else ["Aucun cours"])
        
        desc = st.text_input("Description / Objectifs de la session (ex: Chapitre 5 et 6) - Optionnel")
        
        if st.button("Ajouter au calendrier", use_container_width=True):
            if courses:
                date_str = str(selected_date)
                if date_str not in st.session_state.schedule:
                    st.session_state.schedule[date_str] = []
                st.session_state.schedule[date_str].append({
                    "type": event_type, 
                    "course": selected_course,
                    "description": desc
                })
                auto_save()
                st.rerun()
            else:
                st.error("Ajoute d'abord un cours !")

    with st.expander("🧹 Nettoyer une journée spécifique"):
        col_c1, col_c2 = st.columns([3, 1])
        date_to_clear = col_c1.date_input("Sélectionne la date à vider", key="clear_date")
        if col_c2.button("Vider ce jour", use_container_width=True):
            d_str = str(date_to_clear)
            if d_str in st.session_state.schedule:
                del st.session_state.schedule[d_str]
                auto_save()
                st.success(f"La journée du {d_str} a été vidée !")
                st.rerun()
            else:
                st.warning("Rien n'était prévu à cette date.")

    st.divider()

    def display_month_calendar(year, month):
        mois_noms = ["", "Janvier", "Février", "Mars", "Avril", "Mai", "Juin", "Juillet", "Août", "Septembre", "Octobre", "Novembre", "Décembre"]
        jours_noms = ["Lun", "Mar", "Mer", "Jeu", "Ven", "Sam", "Dim"]
        
        st.markdown(f"### {mois_noms[month]} {year}")
        cols = st.columns(7)
        for i, day in enumerate(jours_noms):
            cols[i].markdown(f"<div style='text-align:center; font-weight:bold; margin-bottom:10px;'>{day}</div>", unsafe_allow_html=True)
            
        cal = calendar.monthcalendar(year, month)
        for week in cal:
            cols = st.columns(7)
            for i, day in enumerate(week):
                if day != 0:
                    with cols[i].container(height=140, border=True):
                        st.markdown(f"<div style='font-weight:bold; text-align:right;'>{day}</div>", unsafe_allow_html=True)
                        date_str = f"{year}-{month:02d}-{day:02d}"
                        
                        if date_str in st.session_state.schedule:
                            for idx, ev in enumerate(st.session_state.schedule[date_str]):
                                course_data = st.session_state.courses.get(ev['course'], {})
                                color = course_data.get("color", "#4CAF50")
                                is_exam = (ev["type"] == "Examen")
                                icon = "🚨" if is_exam else "📚"
                                text_weight = "900" if is_exam else "500"
                                exam_text = "EXAM: " if is_exam else ""
                                
                                st.markdown(f"""
                                <div style="background-color: {color}33; border-left: 4px solid {color}; padding: 4px; border-radius: 4px; margin-bottom: 4px; font-size: 11px;">
                                    <span style="font-weight:{text_weight}; color: black;">{icon} {exam_text}{ev['course']}</span>
                                </div>
                                """, unsafe_allow_html=True)
                else:
                    with cols[i].container(height=140, border=False):
                        st.empty()

    today = datetime.today()
    display_month_calendar(today.year, today.month)
    
    st.write("<br><br>", unsafe_allow_html=True)
    
    next_month = today.month + 1 if today.month < 12 else 1
    next_year = today.year if today.month < 12 else today.year + 1
    display_month_calendar(next_year, next_month)

# -------------------------
# 3. ONGLET PAR COURS
# -------------------------
for tab, cname in zip(tab_objs[2:], courses):
    with tab:
        data = st.session_state.courses[cname]
        tasks = data["tasks"]
        grading = data["grading"]
        color = data["color"]

        st.header(cname)
        if data.get("full_name"):
            st.markdown(f"**{data['full_name']}**")
        if data.get("professor"):
            st.markdown(f"*Professeur : {data['professor']}*")
        
        # --- PARAMÈTRES AVANCÉS DU COURS ---
        with st.expander("⚙️ Paramètres du cours"):
            col_p1, col_p2 = st.columns(2)
            new_name = col_p1.text_input("Acronyme (Nom court)", value=cname, key=f"rn_{cname}")
            new_full_name = col_p2.text_input("Nom complet du cours", value=data.get("full_name", ""), key=f"fn_{cname}")
            
            col_p3, col_p4, col_p5 = st.columns([1, 2, 2])
            new_col = col_p3.color_picker("Couleur", value=color, key=f"cp_{cname}")
            new_prof = col_p4.text_input("Professeur", value=data.get("professor", ""), key=f"pr_{cname}")
            new_pass = col_p5.number_input("Cote cible (sur 20)", value=float(data.get("passing_grade", 10.0)), step=0.5, key=f"pass_{cname}")
            
            st.markdown("**Informations sur l'examen**")
            col_ex1, col_ex2, col_ex3 = st.columns([1, 1, 2])
            
            try:
                ex_s = datetime.strptime(data.get("exam_start_time", "08:30"), "%H:%M").time()
                ex_e = datetime.strptime(data.get("exam_end_time", "10:30"), "%H:%M").time()
            except:
                ex_s = datetime.strptime("08:30", "%H:%M").time()
                ex_e = datetime.strptime("10:30", "%H:%M").time()
                
            new_start = col_ex1.time_input("Début", value=ex_s, key=f"tistart_{cname}")
            new_end = col_ex2.time_input("Fin", value=ex_e, key=f"tiend_{cname}")
            new_loc = col_ex3.text_input("Lieu / Auditoire", value=data.get("exam_location", ""), key=f"loc_{cname}")
            
            if st.button("Enregistrer les modifications", key=f"save_edit_{cname}"):
                st.session_state.courses[cname].update({
                    "color": new_col,
                    "full_name": new_full_name,
                    "professor": new_prof,
                    "passing_grade": new_pass,
                    "exam_start_time": new_start.strftime("%H:%M"),
                    "exam_end_time": new_end.strftime("%H:%M"),
                    "exam_location": new_loc
                })
                
                changed_name = False
                if new_name != cname and new_name.strip() != "":
                    if new_name not in st.session_state.courses:
                        st.session_state.courses[new_name] = st.session_state.courses.pop(cname)
                        for d_str, evs in st.session_state.schedule.items():
                            for e in evs:
                                if e["course"] == cname:
                                    e["course"] = new_name
                        changed_name = True
                    else:
                        st.error("Un cours avec cet acronyme existe déjà.")
                        st.stop()
                
                auto_save()
                st.rerun()

        # Barre PRINCIPALE du cours mise en évidence
        progress_bar(compute_progress(tasks), color, is_main=True)

        # -- TÂCHES --
        with st.expander("➕ Ajouter tâche"):
            tname = st.text_input("Nom", key=f"t_{cname}")
            total = st.number_input("Total", 1, key=f"tt_{cname}")

            if st.button("Ajouter", key=f"add_t_{cname}"):
                tasks.append({"name": tname, "total": float(round(total, 2)), "done": 0.0})
                auto_save()
                st.rerun()

        for i, t in enumerate(tasks):
            st.markdown(f"#### {t['name']}")
            # Barre secondaire plus discrète
            progress_bar(t["done"] / t["total"], color, is_main=False)

            cols = st.columns([2,1,1,1])
            cols[0].write(f"{round(t['done'],2)} / {round(t['total'],2)}")

            if cols[1].button("➖", key=f"m_{cname}_{i}"):
                if t["done"] > 0:
                    t["done"] = round(t["done"] - 1, 2)
                    auto_save()
                    st.rerun()

            if cols[2].button("➕", key=f"p_{cname}_{i}"):
                if t["done"] < t["total"]:
                    t["done"] = round(t["done"] + 1, 2)
                    auto_save()
                    st.rerun()

            if cols[3].button("❌", key=f"d_{cname}_{i}"):
                tasks.pop(i)
                auto_save()
                st.rerun()
            st.markdown("---")

        # -- PLANNING DU COURS --
        st.subheader("🗓️ Planification")
        st.write(f"⏱️ **Total prévu :** {study_days_count[cname]['total']} jour(s)")
        st.write(f"⏳ **Reste à faire :** {study_days_count[cname]['remaining']} jour(s)")
        
        st.markdown("<br>📅 **Dates planifiées :**", unsafe_allow_html=True)
        
        course_dates = []
        for d_str, events in st.session_state.schedule.items():
            for ev in events:
                if ev["course"] == cname:
                    d_obj = datetime.strptime(d_str, "%Y-%m-%d")
                    course_dates.append({"date_obj": d_obj, "type": ev["type"], "desc": ev.get("description", "")})
        
        course_dates.sort(key=lambda x: x["date_obj"])
        
        if course_dates:
            mois_noms_fr = ["", "Jan", "Fév", "Mar", "Avr", "Mai", "Juin", "Juil", "Août", "Sep", "Oct", "Nov", "Déc"]
            for item in course_dates:
                d = item["date_obj"]
                date_formatted = f"{d.day} {mois_noms_fr[d.month]} {d.year}"
                desc_text = f" *(Objectif: {item['desc']})*" if item['desc'] else ""
                
                if item["type"] == "Examen":
                    st.markdown(f"- 🚨 **{date_formatted} (Examen)**{desc_text}")
                else:
                    st.markdown(f"- 📚 {date_formatted}{desc_text}")
        else:
            st.write("- Aucun jour planifié dans le calendrier pour l'instant.")
        
        st.divider()

        # -- COTATION --
        st.subheader("🎓 Cotation")

        with st.expander("➕ Ajouter section"):
            name = st.text_input("Nom", key=f"g_{cname}")
            total = st.number_input("Sur combien de points", 1.0, key=f"gt_{cname}")
            score = st.number_input("Points obtenus", 0.0, key=f"gs_{cname}")

            if st.button("Ajouter section", key=f"add_g_{cname}"):
                grading.append({"name": name, "total": round(total, 2), "score": round(score, 2)})
                auto_save()
                st.rerun()

        for i, g in enumerate(grading):
            cols = st.columns([2,1,1,1])
            cols[0].write(f"**{g['name']} ({round(g['total'],2)} pts)**")

            new_score = cols[1].number_input("Score", value=float(g["score"]), key=f"s_{cname}_{i}")
            if new_score != g["score"]:
                g["score"] = new_score
                auto_save()

            cols[2].write(f"{round((g['total']/20)*100,2)} %")

            if cols[3].button("❌", key=f"dg_{cname}_{i}"):
                grading.pop(i)
                auto_save()
                st.rerun()

        # -- EXAMEN --
        target_grade = data.get("passing_grade", 10.0)
        exam_total, needed = compute_exam_needed(grading, target_grade)
        st.divider()
        st.markdown(f"### 🧪 Examen (Cible: {target_grade}/20)")
        st.write(f"Examen sur **{exam_total:.2f} points**")

        if exam_total > 0:
            st.markdown(f"### 🎯 Tu dois avoir **{needed:.2f} / {exam_total:.2f}** pour atteindre ton objectif")
        else:
            st.success("🎉 Objectif déjà atteint ou dépassé avec la cotation continue !")
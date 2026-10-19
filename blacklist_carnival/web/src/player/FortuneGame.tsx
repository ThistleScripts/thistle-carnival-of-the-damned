import { useEffect, useState } from 'react';
import { api } from '../nui';
import { Backdrop, Icon } from '../components/Art';
import { Button } from '../components/ui';
import { errorText } from '../i18n';
import { playSound } from '../audio';
import { signed } from '../format';

// Typewriter effect for the fortune teller's lines.
function Speech({ text }: { text: string }) {
  const [shown, setShown] = useState('');
  useEffect(() => {
    setShown('');
    let i = 0;
    const t = setInterval(() => {
      i += 2;
      setShown(text.slice(0, i));
      if (i >= text.length) clearInterval(t);
    }, 20);
    return () => clearInterval(t);
  }, [text]);
  return <p className="speech">{shown}</p>;
}

export function FortuneGame({ data, onClose }: { data: any; onClose: () => void }) {
  const [question, setQuestion] = useState<any>(data.question ?? null);
  const [feedback, setFeedback] = useState<any>(null);
  const [finished, setFinished] = useState<boolean>(!!data.finished);
  const [farewell, setFarewell] = useState<string | null>(data.farewell ?? null);
  const [text, setText] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [deadline, setDeadline] = useState<number | null>(null);
  const [now, setNow] = useState(Date.now());

  useEffect(() => {
    setQuestion(data.question ?? null);
    setFinished(!!data.finished);
  }, [data.visitId, data.question?.id]);

  useEffect(() => {
    if (!question) return;
    setDeadline(Date.now() + (question.timeout ?? 90) * 1000);
    setText('');
  }, [question?.id]);

  useEffect(() => {
    const t = setInterval(() => setNow(Date.now()), 500);
    return () => clearInterval(t);
  }, []);

  const answer = async (payload: Record<string, unknown>) => {
    if (!question) return;
    setBusy(true);
    setError(null);
    const r = await api('fortune.answer', { visitId: data.visitId, questionId: question.id, ...payload });
    setBusy(false);
    if (!r.ok || !r.data) {
      setError(errorText(r));
      return;
    }
    const res = r.data;
    setFeedback(res);
    playSound(res.correct ? 'wheel_win' : 'wheel_lose', 0.6);
    if (res.finished) {
      setFinished(true);
      setFarewell(res.farewell ?? null);
      setQuestion(null);
    } else {
      setQuestion(res.question);
    }
  };

  const secondsLeft = deadline ? Math.max(0, Math.ceil((deadline - now) / 1000)) : null;

  return (
    <div className="overlay-center">
      <Backdrop name="fortune" className="panel-frame fortune-frame">
        <header className="frame-head">
          <div className="fortune-title"><Icon name="fortune" size={28} /><h2>The Fortune Teller's Curse</h2></div>
          <Button variant="ghost" onClick={onClose}>{finished ? 'Leave' : 'Step away'}</Button>
        </header>
        {data.greeting && !feedback ? <Speech text={data.greeting} /> : null}
        {data.fortune ? <blockquote className="fortune-text">“{data.fortune}”</blockquote> : null}
        {feedback ? (
          <div className={`fortune-feedback ${feedback.correct ? 'good' : 'bad'}`}>
            <strong>{feedback.timedOut ? 'Too slow…' : feedback.correct ? 'Correct.' : 'Wrong.'}</strong> {feedback.text}
            {feedback.points ? <span className="pill pill-gold">{signed(feedback.points)}</span> : null}
          </div>
        ) : null}
        {question ? (
          <div className="fortune-question">
            <div className="muted small">Question {question.index} of {question.total}{secondsLeft != null ? ` · ${secondsLeft}s` : ''}</div>
            <p className="fortune-prompt">{question.prompt}</p>
            {question.kind === 'choice' ? (
              <div className="choice-grid">
                {(question.choices ?? []).map((c: string, i: number) => (
                  <Button key={i} disabled={busy} onClick={() => answer({ choice: i + 1 })}>{c}</Button>
                ))}
              </div>
            ) : (
              <form className="riddle-form" onSubmit={(e) => { e.preventDefault(); if (text.trim()) answer({ text }); }}>
                <input autoFocus value={text} maxLength={120} onChange={(e) => setText(e.target.value)} placeholder="Speak your answer…" />
                <Button variant="primary" busy={busy} disabled={!text.trim()}>Answer</Button>
              </form>
            )}
          </div>
        ) : null}
        {finished ? <Speech text={farewell ?? 'The cards fall silent.'} /> : null}
        {error ? <div className="state-error">{error}</div> : null}
      </Backdrop>
    </div>
  );
}

export function FortuneCard({ data }: { data: any }) {
  return (
    <div className="side-card fortune-card">
      <Icon name="fortune" size={22} />
      <div><div className="muted small">The fortune teller whispers…</div><p>“{data.text}”</p></div>
    </div>
  );
}
